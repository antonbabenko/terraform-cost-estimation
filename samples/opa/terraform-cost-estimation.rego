# Terraform Cost Estimation + Open Policy Agent
#
# This code snippet supports terraform state for now.
#
# Get the whole response:
# opa eval --data terraform-cost-estimation.rego --input terraform.tfstate --format pretty data.terraform_cost_estimation
# 
# Get boolean response. Return false if state (per hour) is too expensive:
# opa eval --data terraform-cost-estimation.rego --input terraform.tfstate --format pretty data.terraform_cost_estimation.response.allowed

package terraform_cost_estimation

default max_hourly_cost = 0.05

response := output {
  response_cost := http.send({"method": "post", "url": "https://cost.modules.tf", "headers": {"Content-type": "application/json"}, "body": input})

  output := {
    "allowed": max_hourly_cost >= to_number(response_cost.body.hourly),
    "hourly": response_cost.body.hourly,
    "monthly": response_cost.body.monthly,
  }
}
