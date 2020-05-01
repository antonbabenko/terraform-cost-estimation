#  Anonymized, secure and free Terraform Cost Estimation service (cost.modules.tf) which supports Terraform plan (0.12+) and Terraform state (any version).

This repository describes usage of a free cost estimation service which is part of [modules.tf](https://modules.tf) that is currently in active development.

Join the mailing list on [modules.tf](https://modules.tf) to stay updated!

### tldr; Post your Terraform json file (state or plan-file) and get cost estimation:

```
$ terraform state pull | curl -s -X POST -H "Content-Type: application/json" -d @- https://cost.modules.tf/

{"hourly": "0.01", "monthly": "9.07"}
```

## Things you should know about infrastructure costs:

- [x] How much does my infrastructure is going to cost **before** it is created?
- [x] How much does my infrastructure cost **after** it is created (based on Terraform state)?
- [x] What is the **difference in cost** comparing to the current infrastructure (based on Terraform plan)?
- [x] Can I have cost estimation based on Terraform 0.7 state files? Yes, any version of Terraform state files is supported!

## Secrets and sensitive information

As you probably know, **Terraform state and plan files may contain secrets and sensitive information** which you don't want to send anywhere in order to get cost estimates. There is a solution that is supported, secure and easy to put in your continuous automation process.

All you need to do is to process Terraform state or plan file with [terraform.jq file](https://github.com/antonbabenko/terraform-cost-estimation/blob/master/terraform.jq) which is available in this repository.

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


## Example - Get cost estimates during `terraform plan`

The flow is like this:

1. Plan Terraform changes into a plan-file
2. Convert the plan-file into json-file
3. Extract anonymized cost keys from the json-file (optional, but recommended)
4. Send cost keys to cost.modules.tf
5. Process response

Step 3 is recommended if you don't want to send the whole json-file which may contain sensitive information.

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


## Is this production-ready?

It is production-ready if you are using only `aws_instance` resources. :)

More resources are going to be supported in the future.


## Like this? Please follow me and share with your network!

[![@antonbabenko](https://img.shields.io/twitter/follow/antonbabenko.svg?style=flat&label=Follow%20@antonbabenko%20on%20Twitter)](https://twitter.com/antonbabenko)
[![@antonbabenko](https://img.shields.io/github/followers/antonbabenko?style=flat&label=Follow%20@antonbabenko%20on%20Github)](https://github.com/antonbabenko)

Consider support my work on [GitHub Sponsors](https://github.com/sponsors/antonbabenko), [Buy me a coffee](https://www.buymeacoffee.com/antonbabenko), or [Paypal](https://www.paypal.me/antonbabenko).


## Disclaimer

`cost.modules.tf` runs by [Betajob](https://www.betajob.com). We don't save, publish, share with anyone data submitted to the service.
No customer identifiable information used to query pricing systems (check source code of [terraform.jq](https://github.com/antonbabenko/terraform-cost-estimation/blob/master/terraform.jq)).

`terraform-cost-estimation` project managed by [Anton Babenko](https://github.com/antonbabenko).

## License

MIT licensed. See LICENSE for full details.
