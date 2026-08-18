"""Does the AWS translation preserve what each 5G network function guarantees?

A mapping table in a README is a claim. These are the same claims written so
they can fail.

Each test names the 3GPP function, the property that function is required to
hold, and the AWS resource that has to carry it after translation. If a future
change breaks one - a subnet made public, encryption dropped, an extra port
opened - the build goes red and says which network function's guarantee was
lost.

The plan is produced by terraform/test, which calls the same seven modules as
environments/prod with credential validation skipped, so this runs with no AWS
account. `terraform validate` proves the configuration parses; a plan proves
the modules compose and these are the resources that would actually exist.

References:
  3GPP TS 23.501 - System architecture for the 5G System
  docs/COMPLIANCE_MAPPING.md - the SOC 2 / PCI DSS control mapping
"""
import json
import os
import pytest

PLAN = os.path.join(os.path.dirname(__file__), "..", "terraform", "test", "plan.json")


def _flatten(module, out):
    for r in module.get("resources", []):
        out.append(r)
    for child in module.get("child_modules", []):
        _flatten(child, out)
    return out


@pytest.fixture(scope="session")
def resources():
    if not os.path.exists(PLAN):
        pytest.fail(
            "plan.json missing. Generate it with:\n"
            "  cd terraform/test && terraform init -backend=false && "
            "terraform plan -refresh=false -out=tfplan && "
            "terraform show -json tfplan > plan.json"
        )
    with open(PLAN) as f:
        plan = json.load(f)
    # Filter to entries that actually carry a `values` block. Some plan nodes
    # (module wrappers, resources whose attributes are entirely unknown until
    # apply) do not, and every test below reads `values`.
    return [r for r in _flatten(plan["planned_values"]["root_module"], []) if "values" in r]


def of_type(resources, t):
    return [r for r in resources if r["type"] == t]


# ---------------------------------------------------------------------------
# The plan is non-empty. Without this every assertion below passes vacuously
# on an empty list, which is the failure mode that makes a test suite lie.
# ---------------------------------------------------------------------------
def test_plan_is_not_empty(resources):
    assert len(resources) > 50, (
        f"only {len(resources)} resources planned - the modules did not compose"
    )


# ---------------------------------------------------------------------------
# UPF (User Plane Function) -> VPC data plane
#
# The UPF forwards subscriber traffic. It sits behind the control plane and is
# never directly addressable from outside the operator network. If the AWS
# translation puts workloads on public subnets, that isolation is gone.
# ---------------------------------------------------------------------------
def test_upf_workloads_are_not_internet_addressable(resources):
    for svc in of_type(resources, "aws_ecs_service"):
        netcfg = (svc["values"].get("network_configuration") or [{}])[0]
        assert netcfg.get("assign_public_ip") is False, (
            f"{svc['name']}: ECS tasks would get public IPs. The UPF equivalent "
            "must stay unreachable from the internet."
        )


def test_upf_private_subnets_never_auto_assign_public_ips(resources):
    private = [s for s in of_type(resources, "aws_subnet") if s["name"] == "private"]
    assert private, "no private subnets planned"
    for s in private:
        assert s["values"].get("map_public_ip_on_launch") is False, (
            "a private subnet auto-assigns public IPs - anything launched there "
            "becomes internet-addressable by default"
        )


# ---------------------------------------------------------------------------
# HA - docs/HA_PATTERNS.md claims the design survives a facility failure.
# A single-AZ deployment does not, however many subnets it has.
# ---------------------------------------------------------------------------
def test_data_plane_spans_multiple_availability_zones(resources):
    azs = {s["values"]["availability_zone"] for s in of_type(resources, "aws_subnet")}
    assert len(azs) >= 2, (
        f"subnets occupy only {azs}. A single-AZ deployment cannot survive the "
        "facility failure HA_PATTERNS.md claims to handle."
    )


# ---------------------------------------------------------------------------
# AMF (Access and Mobility Management) -> ALB
#
# The AMF is the single controlled entry point for signalling. After
# translation, exactly one thing should accept traffic from the internet.
# ---------------------------------------------------------------------------
def test_amf_is_the_only_internet_facing_entry_point(resources):
    open_to_world = []
    for sg in of_type(resources, "aws_security_group"):
        for rule in sg["values"].get("ingress") or []:
            if "0.0.0.0/0" in (rule.get("cidr_blocks") or []):
                open_to_world.append(sg["name"])
                break
    assert open_to_world == ["alb"], (
        f"security groups open to the internet: {open_to_world}. Only the ALB - "
        "the AMF equivalent - should be. Everything else reaches it through a "
        "security group reference."
    )


# ---------------------------------------------------------------------------
# UDM (Unified Data Management) -> DynamoDB
#
# The UDM holds subscriber identity and session state - the most sensitive
# data in the core. PCI DSS Requirement 3 covers protecting stored data.
# ---------------------------------------------------------------------------
def test_udm_subscriber_store_is_encrypted_at_rest(resources):
    tables = of_type(resources, "aws_dynamodb_table")
    assert tables, "no subscriber store planned"
    for t in tables:
        sse = (t["values"].get("server_side_encryption") or [{}])[0]
        assert sse.get("enabled") is True, (
            f"{t['values']['name']}: subscriber state unencrypted at rest "
            "(PCI DSS Req 3)"
        )


def test_udm_subscriber_store_is_recoverable(resources):
    for t in of_type(resources, "aws_dynamodb_table"):
        pitr = (t["values"].get("point_in_time_recovery") or [{}])[0]
        assert pitr.get("enabled") is True, (
            f"{t['values']['name']}: no point-in-time recovery. Losing subscriber "
            "state to an accidental write has no undo."
        )


# ---------------------------------------------------------------------------
# OAM event bus -> Kinesis
#
# Operational telemetry carries subscriber identifiers, so it is in scope for
# the same encryption requirement as the datastore.
# ---------------------------------------------------------------------------
def test_oam_event_stream_is_encrypted(resources):
    streams = of_type(resources, "aws_kinesis_stream")
    assert streams, "no event bus planned"
    for s in streams:
        assert s["values"].get("encryption_type") == "KMS", (
            f"{s['name']}: event stream not KMS-encrypted, but OAM events carry "
            "subscriber identifiers"
        )


# ---------------------------------------------------------------------------
# NRF (Network Repository Function) -> Cloud Map
#
# Network functions find each other through the NRF rather than by address.
# Without service discovery the translation reintroduces static addressing.
# ---------------------------------------------------------------------------
def test_nrf_service_discovery_exists_and_is_used(resources):
    namespaces = of_type(resources, "aws_service_discovery_private_dns_namespace")
    assert namespaces, "no service discovery namespace - the NRF has no equivalent"

    services = of_type(resources, "aws_ecs_service")
    assert services, "no ECS services planned"
    for svc in services:
        assert svc["values"].get("service_registries"), (
            f"{svc['name']}: not registered for discovery. Network functions "
            "would have to find each other by address."
        )


# ---------------------------------------------------------------------------
# PCF (Policy Control Function) -> AWS Config
#
# The PCF enforces policy across every session at runtime. The AWS equivalent
# is only real if the recorder is on AND rules are attached - a recorder with
# no rules records everything and enforces nothing.
# ---------------------------------------------------------------------------
def test_pcf_policy_enforcement_is_actually_configured(resources):
    recorders = of_type(resources, "aws_config_configuration_recorder")
    rules = of_type(resources, "aws_config_config_rule")
    assert recorders, "no Config recorder - the PCF equivalent does not exist"
    assert len(rules) >= 4, (
        f"only {len(rules)} Config rules. A recorder with no rules observes "
        "everything and enforces nothing."
    )


# ---------------------------------------------------------------------------
# PCI DSS Requirement 10 - track and monitor all access.
# ---------------------------------------------------------------------------
def test_audit_trail_is_enabled(resources):
    trails = of_type(resources, "aws_cloudtrail")
    assert trails, "no CloudTrail - PCI DSS Req 10 has no evidence"
    for t in trails:
        assert t["values"].get("is_multi_region_trail") is not False, (
            "single-region trail: activity in another region is unrecorded"
        )


# ---------------------------------------------------------------------------
# Cost attribution. Untagged infrastructure cannot be charged back, and
# unattributable spend is the spend nobody cleans up.
# ---------------------------------------------------------------------------
TAGGABLE = (
    "aws_vpc",
    "aws_subnet",
    "aws_ecs_cluster",
    "aws_dynamodb_table",
    "aws_kinesis_stream",
    "aws_lb",
)


def test_every_major_resource_carries_project_tags(resources):
    # tags_all, not tags. Provider-level `default_tags` are merged into
    # tags_all; the `tags` field holds only what the resource sets itself.
    # Checking `tags` reports every resource as untagged even when the
    # provider is tagging all of them - which is exactly what this test did
    # on its first run.
    missing = []
    for r in resources:
        if r["type"] not in TAGGABLE:
            continue
        tags = r["values"].get("tags_all") or {}
        if "Project" not in tags:
            missing.append(f"{r['type']}.{r['name']}")
    assert not missing, f"resources with no Project tag: {missing}"


# ---------------------------------------------------------------------------
# Traceability back to the source architecture.
#
# Every resource carries a NokiaMapping tag naming the 5G network function it
# replaces. That is what makes the migration reviewable by someone who knows
# the carrier side but not AWS: they can ask "where did the UPF go" and get an
# answer from the infrastructure itself rather than from a diagram that may
# have drifted.
# ---------------------------------------------------------------------------
CORE_FUNCTIONS = ("UPF", "AMF", "SMF", "NRF", "UDM", "PCF", "CBAM", "OAM", "SBI")


def test_every_core_network_function_is_represented(resources):
    mapped = {
        (r["values"].get("tags_all") or {}).get("NokiaMapping", "").split("-")[0]
        for r in resources
        if (r["values"].get("tags_all") or {}).get("NokiaMapping")
    }
    absent = [fn for fn in CORE_FUNCTIONS if fn not in mapped]
    assert not absent, (
        f"no resource maps to {absent}. Either the function was dropped in "
        "translation or its resources lost the NokiaMapping tag."
    )


def test_mapped_resources_are_a_meaningful_share_of_the_stack(resources):
    # Guards the test above from passing on a handful of tagged resources
    # while most of the estate is untraceable.
    mapped = sum(
        1 for r in resources if (r["values"].get("tags_all") or {}).get("NokiaMapping")
    )
    taggable = sum(1 for r in resources if "tags_all" in r["values"])
    assert taggable, "no taggable resources planned"
    ratio = mapped / taggable
    assert ratio >= 0.5, (
        f"only {mapped}/{taggable} ({ratio:.0%}) of taggable resources trace back "
        "to a network function"
    )
