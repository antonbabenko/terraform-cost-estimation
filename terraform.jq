# This jq-file extracts cost keys from given Terraform file (plan as json and any version of Terraform state).
#
# jq version 1.6 or newer is required.
#
# Repository: https://github.com/antonbabenko/terraform-cost-estimation
# License: MIT

def parse_arn:
  split(":")[3] # Take region
;

def get_cost_keys_from_resource_instances:
  {
    region: (.arn | parse_arn? // $ENV.AWS_DEFAULT_REGION // $ENV.AWS_REGION),
    tenancy: (if .tenancy == "dedicated" then "dedicated" else "shared" end),
    instance_type
  }
;

def construct_cost_key:
  {
    platform: "linux",
    prefix: "ec2"
  } as $v
  | [
      $v.prefix
    , .region
    , .instance_type
    , .tenancy
    , $v.platform
    ]
  | join("#")
  | ascii_downcase
;

def extract_cost_info:
  get_cost_keys_from_resource_instances
  | construct_cost_key
;

def extract_tfstate: # ---------------------------------- Terraform 0.12 tfstate
  .resources[]
  | select(.type == "aws_instance")
  | .instances[].attributes
  | extract_cost_info
;

def extract_plan: # ---------------------------------------- Terraform 0.12 plan
  .resource_changes[]
  | select(.type == "aws_instance")
  | .change
  | {
      after: (.after | if . then (extract_cost_info) else null end),
      before: (.before | if . then (extract_cost_info) else null end),
    }
;

def extract_old: # ---------------------------------------- Terraform 0.7 - 0.11
  .modules[].resources[]
  | select(.type == "aws_instance")
  | .primary.attributes
  | extract_cost_info
;

def extract_data:
  if .resources then
    extract_tfstate
  elif .resource_changes then
    extract_plan
  elif .modules then
    extract_old
  else empty
  end
;

def parse:
  {
    version: "0.1.0",
    keys: [extract_data],
  }
;

parse