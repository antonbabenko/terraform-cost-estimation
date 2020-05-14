#  Anonymized, secure and free Terraform Cost Estimation

`cost.modules.tf` is entirely free cost estimation service, which is part of [modules.tf](https://modules.tf) that is currently in active development.

Join the mailing list on [modules.tf](https://modules.tf) to stay updated!

## tldr; Post your Terraform state or plan-file (as JSON) and get cost estimation:

```
$ terraform state pull | curl -s -X POST -H "Content-Type: application/json" -d @- https://cost.modules.tf/

{"hourly": "0.01", "monthly": "9.07"}
```

NB: Cost estimation uses official [AWS pricing data](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/price-changes.html) and does not include estimates for items not specified in Terraform configurations (e.g., usage patterns, amount of API calls, bandwidth, disk I/O, spot prices, AWS discounts, etc.).

See the list of [supported resources](#supported-resources).


## Secrets and sensitive information

As you probably know, **Terraform state and plan files may contain secrets and sensitive information** which you don't want to send anywhere to get cost estimates. There is a solution that is supported, secure, and easy to put in your continuous automation process.

All you need to do is to process the Terraform state or plan file with [terraform.jq file](https://github.com/antonbabenko/terraform-cost-estimation/blob/master/terraform.jq) which is available in this repository.

`terraform.jq` creates _anonymized cost keys_ sufficient to perform cost estimation. Nothing more.

The whole process looks like this:

```
# Install jq version 1.6 or newer - https://stedolan.github.io/jq/download/

# Download terraform.jq file
$ curl -sLO https://raw.githubusercontent.com/antonbabenko/terraform-cost-estimation/master/terraform.jq

# Get terraform state (or plan), extract cost keys, send them to cost estimation service
$ terraform state pull | jq -cf terraform.jq | curl -s -X POST -H "Content-Type: application/json" -d @- https://cost.modules.tf/

{"hourly": "0.01", "monthly": "9.07"}
```

Sweet, isn't it?


## Things you should know about infrastructure costs:

- [x] How much does my infrastructure is going to cost **before**  create?
- [x] How much does my infrastructure cost **after** it is created (based on Terraform state)?
- [x] What is the **difference in the price** comparing to the current infrastructure (based on Terraform plan)?
- [x] Can I have cost estimation based on Terraform 0.7 state files? Yes, any version of Terraform state files is supported!


## Example - Get cost estimates during `terraform plan`

The flow is like this:

1. Plan Terraform changes into a plan-file
2. Convert the plan-file into JSON-file
3. Extract anonymized cost keys from the JSON-file (optional, but recommended)
4. Send cost keys to cost.modules.tf
5. Process response

Step 3 recommended if you don't want to send the whole JSON-file, which may contain sensitive information.

The whole command looks like this:

```
# Install jq and download `terraform.jq` file as described in "secrets and sensitive information" section

$ terraform plan -out=plan.tfplan > /dev/null && terraform show -json plan.tfplan | jq -cf terraform.jq | curl -s -X POST -H "Content-Type: application/json" -d @- https://cost.modules.tf/
```

Alternatively, you can send the whole Terraform plan-file without modification as json, too:

```
$ terraform plan -out=plan.tfplan > /dev/null && terraform show -json plan.tfplan | curl -s -X POST -H "Content-Type: application/json" -d @- https://cost.modules.tf/
```


### Helpers

```
# Get Terraform plan as json
$ terraform plan -out=plan.tfplan > /dev/null && terraform show -json plan.tfplan > plan.json

# Get Terraform state as json (option 1)
$ terraform state pull > plan.json

# Get Terraform state as json (option 2)
$ terraform show -json > plan.json

# Do something is monthly cost is too high
$ ... | curl -s -X POST -H "Content-Type: application/json" -d @- https://cost.modules.tf/ > costs.json
$ jq 'if .monthly|tonumber > 10 then "$" else "$$$" end' costs.json
```


## Supported resources

1. EC2 instances (on-demand) and Autoscaling Groups (Launch Configurations and Launch Templates):
- [x] aws_instance
- [x] aws_autoscaling_group
- [x] aws_launch_configuration
- [x] aws_launch_template

2. EC2 Fleets (on-demand)
- [x] aws_ec2_fleet

3. EBS Volumes, Snapshots, Snapshot Copies
- [x] aws_ebs_volume
- [x] aws_ebs_snapshot
- [x] aws_ebs_snapshot_copy

4. Elastic Load Balancing (ELB, ALB, NLB)
- [x] aws_elb
- [x] aws_alb / aws_lb

5. NAT Gateways
- [x] aws_nat_gateway


Please suggest other resources worth covering by upvoting existing issue or opening new issue.

As [AWS Community Hero](https://aws.amazon.com/developer/community/heroes/anton-babenko/), I work a lot with AWS, but I am equally interested in covering other popular [Terraform Providers](https://www.terraform.io/docs/providers/) with decent pricing API.


## Like this? Please follow me and share it with your network!

[![@antonbabenko](https://img.shields.io/twitter/follow/antonbabenko.svg?style=flat&label=Follow%20@antonbabenko%20on%20Twitter)](https://twitter.com/antonbabenko)
[![@antonbabenko](https://img.shields.io/github/followers/antonbabenko?style=flat&label=Follow%20@antonbabenko%20on%20Github)](https://github.com/antonbabenko)

Consider support my work on [GitHub Sponsors](https://github.com/sponsors/antonbabenko), [Buy me a coffee](https://www.buymeacoffee.com/antonbabenko), or [PayPal](https://www.paypal.me/antonbabenko).


## Disclaimer

`cost.modules.tf` runs by [Betajob](https://www.betajob.com). We don't save, publish, share with anyone data submitted to the service.
No identifiable customer information used to query pricing systems (check source code of [terraform.jq](https://github.com/antonbabenko/terraform-cost-estimation/blob/master/terraform.jq)).

`terraform-cost-estimation` project managed by [Anton Babenko](https://github.com/antonbabenko).

## License

MIT licensed. See LICENSE for full details.
