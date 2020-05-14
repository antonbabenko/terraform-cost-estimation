# This jq-file extracts cost keys from given Terraform file (plan as json and any version of Terraform state).
#
# jq version 1.6 or newer is required.
#
# Repository: https://github.com/antonbabenko/terraform-cost-estimation
# License: MIT

def debug($msg): $msg | debug | empty;
def outline($msg): "---> \($msg)";

def isnull: . == null;
def isstr: type == "string";
def isarray: type == "array";
def isobject: type == "object";
def isiterable: type|. == "array" or . == "object";
def isblankstr: type == "string" and . == "";
def isblank: isiterable and (.|length) == 0;
def isidle: isnull or isblankstr or isblank;
def idle_paths: [path(..|select(isidle))];
def del_nulls: delpaths([paths(isnull)]);
def del_blanks: delpaths([paths(isblank)]);
def del_idles: delpaths(idle_paths);
def del_idles_recursive:
        walk(if isidle then . elif isiterable then delpaths([paths(isidle)]) else . end);
def getpaths(PATHS): . as $in | reduce PATHS[] as $p ({}; .[$p[0]] = ($in | getpath($p)));
def uniq: reduce .[] as $x ([]; if . | contains([$x]) | not then . + [$x] else . end);
def insideof($g): . as $i| $g | map(.==$i) | any;
def mul: reduce .[] as $x(1; .*$x);
def array_mul_tail: [.[0],(.[1:]|mul)];
def array_group_sum:
    group_by(.[0]) as $x|[$x[]|reduce .[] as $x(["", 0]; [$x[0], .[1]+$x[1]])]
;
def pack_cost_keys: map(join("|"));
def compact_cost_keys:
    sort_by(.[0]) | array_group_sum | pack_cost_keys
;


def vars:
    {
        platform: "linux",
        ec2_prefix: "ec2",
        fallback_region: ($ENV.AWS_DEFAULT_REGION // $ENV.AWS_REGION // "eu-west-1")
    }
;

def group_resources:
    group_by(.)[]|[.[0], (.|length)] | join("|")
;

def group_and_sum:
    reduce .[] as $x (
        {}; if .[$x[0]] == null
            then .[$x[0]]=$x[1]
            else .[$x[0]]+=$x[1] end)
;

def parse_arn:
    split(":")[3] # Take region
;

def get_cost_keys_from_ec2_instances:
    vars as $v
    | {
        region: (.arn | parse_arn? // $v.fallback_region),
        tenancy: (if .tenancy != "dedicated" then "shared" else . end),
        instance_type,
        capacity: (.capacity // 1),
    }
;

def construct_ec2_cost_key:
    vars as $v
    |[  ([
            $v.ec2_prefix
            , .region
            , .instance_type
            , .tenancy
            , $v.platform
        ]
        | join("#")
        | ascii_downcase)
        , .capacity
    ]   #| join("|")
;

def extract_ec2_cost_info:
    get_cost_keys_from_ec2_instances
    | construct_ec2_cost_key
;

def get_cost_keys_from_gpu_instances:
    vars as $v
    |{
        region: (.arn | parse_arn? // $v.fallback_region),
        gpu_type: .elastic_gpu_specifications[].type,
        capacity: (.capacity // 1),
        instance_type,
        id,
    }
;

def construct_gpu_cost_key:
    vars as $v
    |[  ([
            $v.ec2_prefix
            , .region
            , .gpu_type
        ]
        | join("#")
        | ascii_downcase)
        , .capacity
    ]   #| join("|")
;

def extract_gpu_cost_info:
    get_cost_keys_from_gpu_instances
    | construct_gpu_cost_key
;


def aws:
    ################################################################# Guards
    def exists(pth):
        if pth != null then
            pth
        else
            . as $i |
            path(pth) as $p |
            $p | join(".") as $d |
            $i | getpath($p[:-1])|keys|join(", ") as $t |
            error("Path \".\($d)\" doesn't found in a json file.\n"
                + "Same level keys: \($t)")
        end
    ;
    ################################################################# Adapters
    def tf_lt_12_adapter:
        [   .modules[].resources
            |to_entries[]
            |{  name: .key,
                type: .value.type,
                instances:[.value.primary + {dependencies:.value.depends_on}]
            }]
    ;
    ################################################################# Data shapers
    def clear_io(expr):
        del_idles_recursive | [expr | del_idles_recursive]
    ;
    def shape_attributes:
        {
            id, arn, instance_type,
            # Autoscaling groups specific
            min_size, spot_price, desired_capacity,
            # LB specific
            load_balancer_type,
            # Launch templates and configuration specific
            launch_configuration,
            launch_template: [.launch_template[]? // {} | {id}],
            launch_template_config:
                [.launch_template_config[]? // {} | {
                    launch_template_specification:
                        [.launch_template_specification[]? // {} | {
                            launch_template_id
                        }]
                }],
            # GPU specific
            elastic_gpu_specifications:
                [.elastic_gpu_specifications[]? // {} | {type}],
            # EC2 fleet specific
            target_capacity_specification:
                [.target_capacity_specification[]? // {} | {
                    default_target_capacity_type,
                    total_target_capacity,
                }],
            # EBS specific
            device_name,
            volume_size,
            volume_type,
            iops,
            type,
            size,
            source_region,
        }
    ;
    def shape_resources(root):
        root |
        {   #"module", mode, each, name,
            type, provider,
            instances: [.instances[]? // {} | {
                attributes: .attributes | shape_attributes,
                #dependencies,
            }]
        }
    ;
    def shape_resource_changes(root):
        root |
        {   "module", mode, each, name, address,
            type, provider_name,
            change: .change | {
                before: .before | shape_attributes,
                after: .after | shape_attributes
            },
        }
    ;
    ################################################################# Data extractors
    def extract_resources:
        if .modules then clear_io(shape_resources(tf_lt_12_adapter[]))
        elif .resources then clear_io(shape_resources(.resources[]))
        else error("Can't read resources")
        end
    ;
    def extract_resource_changes:
        if .resource_changes then clear_io(shape_resource_changes(.resource_changes[]))
        else error("Can't read resource_changes")
        end
    ;
    def aws_ebs_block_devices(attr; inst):
        def extract(cond; cost_type):
            vars as $v |
            map(select(cond))[]
                | . as $r
                | inst
                | if (type| . == "object") then [.] else . end # hack for plans
                |. [] | attr
                | { region: (.arn | parse_arn? // $v.fallback_region),
                    cost_type: cost_type,
                    type: $r.type,
                    volume_size: (.volume_size // 0),
                    size: (.size // 0),
                    iops: (.iops // 0),
                    source_region: (.source_region // $v.fallback_region),
                }
        ;
        [(
            extract(.type == "aws_ebs_snapshot"; "snapshot"),
            extract(.type == "aws_ebs_snapshot_copy"; "snapshot"),
            extract(.type == "aws_ebs_volume";
                    if .type == "standard" then "standard"
                    elif .type == "io1" then "io1"
                    else "gp2" end)
        ) | (
                if .type == "aws_ebs_snapshot" then
                    ["ec2#\(.region)#\(.cost_type)", .volume_size]
                elif .type == "aws_ebs_snapshot_copy" then
                    ["ec2#\(.source_region)#\(.cost_type)", .volume_size]
                elif .type == "aws_ebs_volume" then (
                    if .cost_type == "io1" then
                        ["ec2#\(.region)#\(.cost_type)", .size],
                        ["ec2#\(.region)#piops", .iops]
                    else
                        ["ec2#\(.region)#\(.cost_type)", .size]
                    end
                )
                else ["ec2#\(.region)#\(.cost_type)", .size]
                end
            )
        ]
    ;
    def aws_ec2_fleet(attr; inst):
        [   map(select(.type == "aws_ec2_fleet" and inst))[] // {}
            | (inst // {})
            | map(attr)[] // {}
            | select(   # Common filtration on instances level
                .target_capacity_specification[]?
                |   .default_target_capacity_type == "on-demand"
                    and .total_target_capacity > 0
            )
            | [ .target_capacity_specification[]?   # Gathering all capacities
                | select(.default_target_capacity_type == "on-demand"
                        and .total_target_capacity > 0)
                | .total_target_capacity
              ] as $capacities
            | .launch_template_config[]? // {}
            | .launch_template_specification[]? // {}
            | {launch_template_id, capacity: $capacities | add}
            #| {(.launch_template_id): .capacity}
            | [.launch_template_id, .capacity]
        ] | group_and_sum
    ;
    def aws_instance(attr; inst):
        [   map(select(.type == "aws_instance" and inst))[] // empty
            | inst // {}
            | if (type| . == "object") then [.] else . end # hack for plans
        ] | add // []
        | map(attr)
    ;
    def aws_autoscaling_group(inst):
        #select(contains({type: "aws_autoscaling_group"}))
        map(select(.type == "aws_autoscaling_group" and inst))
    ;
    def ag_filter(attr):
        # Filtration of autoscaling groups that doesn't fit.
        map(select(
            attr.desired_capacity>=1
            or attr.min_size>=1
            or attr.spot_price
        ))
    ;
    def ag_instances(attr; inst):
        [   .[]
            | inst
            | if (type| . == "object") then [.] else . end # hack for plans
        ] | (add // [])
    ;
    def ag_instances_with_lt(attr):
        map(select(attr.launch_template))
    ;
    def ag_instances_with_lc(attr):
        map(select(attr.launch_configuration))
    ;
    def lt_ids(attr):
        [.[] | attr.launch_template[].id] | uniq
    ;
    def lc_ids(attr):
        [.[] | attr.launch_configuration] | uniq
    ;
    def desired_capacities(attr; inst):
        [   .[] | inst
            | if (type| . == "object") then [.] else . end # hack for plans
            | .[] | attr as $a | $a
            | [.launch_configuration? // (.launch_template? // [] | .[].id)] #as $ids
            | .[] | [., ($a.desired_capacity | if . == 0 then $a.min_size // 0 else . end)]
        ]   | group_and_sum # => {launch_..._id: total_desired_capacity}
    ;
    def aws_launch_template(inst):
        map(select(.type == "aws_launch_template" and inst))
    ;
    def aws_launch_configuration(inst):
        map(select(.type == "aws_launch_configuration" and inst))
    ;
    def launch_instances($ids; attr; inst):
        [[.[] | inst
        | if (type | . == "object") then [.] else . end # hack for plans
        ] | (add // [])[] | select(attr.id|insideof($ids))]
        | map(attr) # Reduce depth
    ;
    def bind_capacities($caps):
        [.[] | . + {capacity: $caps[.id]}]
    ;
    ################################################################# Compute costs funcs
    def cost_instances:
        map(extract_ec2_cost_info)
    ;
    def cost_gpus:
        map(extract_gpu_cost_info)
    ;
    def aws_loadbalancers(attr; inst):
        def extract(cond; _type):
            vars as $v |
            map(select(cond))[]
                | inst
                | if (type | . == "object") then [.] else . end # hack for plans
                | .[] | attr
                | { region: (.arn | parse_arn? // $v.fallback_region),
                    type: _type}
        ;
        [(
            extract(.type == "aws_lb" or .type == "aws_alb";
                    if .load_balancer_type == "network" then "nlb" else "alb" end),
            extract(.type == "aws_elb"; "elb"),
            extract(.type == "aws_nat_gateway"; "nat")
        ) | ["ec2#\(.region)#\(.type)", 1]]
        #| group_resources
    ;
    ################################################################# Process data
    def process_resources(attr; inst):
        . as $r |
        aws_instance(attr; inst) as $ai |
        aws_autoscaling_group(inst) as $ag |
        ($ag | ag_instances(attr; inst)
                | ag_filter(attr)) as $agi |
        ($agi | ag_instances_with_lt(attr)) as $ilt |
        ($agi | ag_instances_with_lc(attr)) as $ilc |
        ($ilt | lt_ids(attr)) as $lti |
        ($ilc | lc_ids(attr)) as $lci |
        ($ag | desired_capacities(attr; inst)) as $dc |
        (aws_launch_template(inst)) as $lt |
        ($lt | launch_instances($lti; attr; inst)
                | bind_capacities($dc)) as $lt_ins |
        (aws_launch_configuration(inst)) as $lc |
        ($lc | launch_instances($lci; attr; inst)
                | bind_capacities($dc)) as $lc_ins |
        aws_ec2_fleet(attr; inst) as $af |
        ($lt | launch_instances(($af|keys); attr; inst)
                | bind_capacities($af)) as $af_ins |
        ################################################################ Compute costs
        ($ai | cost_instances) as $cai |
        ($lt_ins | cost_instances) as $clti |
        ($lt_ins | cost_gpus) as $cgti |
        ($lc_ins | cost_instances) as $clci |
        ($lc_ins | cost_gpus) as $cgci |
        ($af_ins | cost_instances) as $cafi |
        aws_loadbalancers(attr; inst) as $lb |
        aws_ebs_block_devices(attr; inst) as $ebs |
        ($cai + $clti + $cgti + $clci + $cgci + $lb + $cafi + $ebs) as $ck
        ############################################################### Result object
        | {
            resources: $r,
            instances: $ai,
            autoscaling_groups: {
                groups: $ag,
                instances: {
                    all: $agi,
                    lt: {
                        instances: $ilt,
                        ids: $lti,
                    },
                    lc: {
                        instances: $ilc,
                        ids: $lci,
                    },
                },
                capacities: $dc,
            },
            ec2_fleets: {
                capacities: $af,
                instances: $af_ins,
            },
            launch_template: {
                instances: $lt_ins,
            },
            launch_configuration: {
                instances: $lc_ins,
            },
            cost: {
                loadbalancers: $lb | pack_cost_keys,
                instances: $cai | pack_cost_keys,
                ec2_fleet: {
                    instances: $cafi | pack_cost_keys,
                },
                launch_template: {
                    instances: $clti | pack_cost_keys,
                    gpu_instances: $cgti | pack_cost_keys,
                },
                launch_configuration: {
                    instances: $clci | pack_cost_keys,
                    gpu_instances: $cgci | pack_cost_keys,
                },
                block_devices: $ebs | pack_cost_keys,
                keys: $ck | compact_cost_keys,
            },
        }
    ;
    def process_resource_changes:
        . as $r | $r
        | process_resources(.change.before; .) as $before
        | process_resources(.change.after; .) as $after
        | {
            #before: $before | del_idles_recursive,
            #after: $after | del_idles_recursive,
            cost: {
                loadbalancers: {
                    before: $before.cost.loadbalancers,
                    after: $after.cost.loadbalancers,
                },
                instances: {
                    before: $before.cost.instances,
                    after: $after.cost.instances,
                },
                ec2_fleet: {
                    before: $before.cost.ec2_fleet,
                    after: $after.cost.ec2_fleet,
                },
                launch_template: {
                    before: $before.cost.launch_template,
                    after: $after.cost.launch_template,
                },
                launch_configuration: {
                    before: $before.cost.launch_configuration,
                    after: $after.cost.launch_configuration,
                },
                block_devices: {
                    before: $before.cost.block_devices,
                    after: $after.cost.block_devices,
                },
                keys: {
                    before: $before.cost.keys,
                    after: $after.cost.keys,
                }
            }
        }
    ;
    def process:
        if .modules or .resources then
            extract_resources | process_resources(.attributes; .instances)
        elif .resource_changes then
            . | extract_resource_changes | process_resource_changes
        else error("Unknown json file structure")
        end
    ;
    process
;

def AWS:
    ############################################################### Shortcuts object
    aws |
    {
        r: .resources,
        i: .instances,
        f: .ec2_fleets,
        lt: .launch_template,
        lc: .launch_configuration,
        ag: .autoscaling_groups,
        c: .cost,
    }
;

def parse:
  {
    version: "0.2.0",
    keys: aws.cost.keys,
  }
;


empty
, parse
, if $ARGS.named.extra != null then
	outline("Extra info")
	, aws
  else empty
  end

# vim:ts=4:sw=4:et
