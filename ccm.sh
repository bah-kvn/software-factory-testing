#!/bin/bash -e
export AMI="ami-08b68a787bb9cf0f3"      # CIS RHEL 7 STIG AMI
export BASE=$PWD
export PROJECT="main-$GH_USERNAME"
export ACCOUNT=$(echo $AWS_DEFAULT_PROFILE | cut -d '-' -f2)
echo "Project = $PROJECT"
export DEST=$HOME/factory/$PROJECT #change this to the directory the code to live
export ARTIFACTS=$HOME/factory/artifacts #change this to the directory the code to live
export DOMAIN="bsf-testing.com"
export AGE_KEY_FILE="$HOME/.ssh/default.age" #file is read to get the AGE public and private keys
export PUBLIC_KEY="$( cat $AGE_KEY_FILE | grep public | cut -d ' ' -f4 )"
export PRIVATE_KEY="$( cat $AGE_KEY_FILE | grep -v "^#" )"
export SOPS_AGE_KEY="$PRIVATE_KEY"
export INGRESS_CIDRS="128.229.4.0/24,156.80.4.0/24,128.229.67.0/24"
#render the template from your branch

copier \
  -d age_key_file="$AGE_KEY_FILE" \
  -d age_secret_key="$PRIVATE_KEY" \
  -d age_public_key="$PUBLIC_KEY" \
  -d aws_region="us-east-1" \
  -d aws_ami="$AMI" \
  -d blueprint="rke-single-cluster" \
  -d byo_cert=false \
  -d project_name="$PROJECT" \
  -d domain="$DOMAIN" \
  -d ib_user="$REGISTRY1_SA_USERNAME" \
  -d ib_token="$REGISTRY1_SA_PASSWORD" \
  -d ingress_cidrs="$INGRESS_CIDRS" \
  -d git_repo="https://github.com/boozallen/software-factory-testing.git" \
  -d git_branch="$PROJECT" \
  -d git_user="$GH_USERNAME" \
  -d git_pat="$GH_PASSWORD" \
  -d dev_environment="staging" \
  -d should_assume_role=true \
  -d assume_role="arn:aws:iam::$ACCOUNT:role/TerraformDeployer" \
  -d cert=false \
  -d perm_boundaries=true \
  -d perm_boundary_needed=true \
  -d email="dev@bah.com" \
  -d hosted_zone_id="Z05620741ABABDDEC0B4Z" \
  -d iam_users_perm_boundary="arn:aws:iam::$ACCOUNT:policy/BAH_User_Policy_Boundary" \
  --overwrite \
  -r "main" \
  gh:boozallen/software-factory $DEST
yq e ".addons.argocd.enabled = false" -i $DEST/cluster/add-ons/bigbang/values.yaml
yq e ".kyverno.enabled = false" -i $DEST/cluster/add-ons/bigbang/values.yaml
yq e ".kiali.enabled = false" -i $DEST/cluster/add-ons/bigbang/values.yaml
yq e ".kyvernoPolicies.enabled = false" -i $DEST/cluster/add-ons/bigbang/values.yaml
yq e ".loki.enabled = false" -i $DEST/cluster/add-ons/bigbang/values.yaml
yq e ".monitoring.enabled = false" -i $DEST/cluster/add-ons/bigbang/values.yaml
yq e ".promtail.enabled = false" -i $DEST/cluster/add-ons/bigbang/values.yaml
yq e ".neuvector.enabled = false" -i $DEST/cluster/add-ons/bigbang/values.yaml
yq e ".tempo.enabled = false" -i $DEST/cluster/add-ons/bigbang/values.yaml
yq e ".domain = strenv(DOMAIN)" -i $DEST/cluster/add-ons/bigbang/values.yaml
yq e ".global.domain = strenv(DOMAIN)" -i $DEST/config.yaml
yq e '.istio.ingressGateways.public-ingressgateway.type = "LoadBalancer"' -i $DEST/cluster/add-ons/bigbang/values.yaml
tee -a $DEST/cluster/add-ons/bigbang/infra/main.tf <<EOF

  resource "kubernetes_config_map" "bigbang-istio-annotations" {
  metadata {
    name      = "bigbang-istio-annotations"
    namespace = "bigbang"
  }
  data = var.configmap_data
}
EOF
sed -i '' "s/})$//g" $DEST/cluster/add-ons/bigbang/terragrunt.hcl

echo '''
include "global" {
  path = find_in_parent_folders()
  expose = true
}

locals {
  global = include.global.locals.config.global
  cluster = include.global.locals.config.cluster
  config = {
    permissions_boundary = try(include.global.locals.config.global.aws.iam_users_perm_boundary, null)
  }
  inputs = {
    for field, value in local.config:
      field => value
      if value != null
  }
}

dependency "networking" {
  config_path = "${get_repo_root()}/infra/networking"
}

dependency "cluster" {
  config_path = "${get_repo_root()}/cluster/infra"
}

terraform { 
  source = "./infra"
}

inputs = merge(local.inputs, { 
  cluster_auth         = dependency.cluster.outputs.cluster_auth
  cluster_name         = local.cluster.cluster_name
  name                 = local.global.stack_name
  output = {
    name = "bigbang-loki-tf-secret"
    namespace = "bigbang"
  }

  namespace      = "bigbang"
  configmap_name = "istio-ingress-annotations"
  configmap_data = {
    "values.yaml" = yamlencode({
      istio = {
        ingressGateways = {
          public-ingressgateway = {
            kubernetesResourceSpec = {
              serviceAnnotations = {
                "service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules" = "false"
                "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
                "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
                "service.beta.kubernetes.io/aws-load-balancer-type" = "external"
                "external-dns.alpha.kubernetes.io/hostname" = "*.${local.cluster.cluster_name}.${local.global.domain}"
                "service.beta.kubernetes.io/aws-load-balancer-name" = "${local.cluster.cluster_name}-public-ingress"
                "service.beta.kubernetes.io/aws-load-balancer-security-groups" = "${dependency.cluster.outputs.rke2.cluster_sg}"
                "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(", ", flatten(dependency.networking.outputs.public_subnets))
                "service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags" = ["kubernetes.io/cluster/${local.cluster.cluster_name}", "owned"]
              }
            }
          }
        },
          gateways = {
            public = {
              hosts = ["*.${local.cluster.cluster_name}.${local.global.domain}"]
              tls = { "credentialName":"public-cert" } } }
      }
    })
  }
})

''' > $DEST/cluster/add-ons/bigbang/terragrunt.hcl
echo '''
variable "configmap_data" {
  type        = map(string)
  default     = {}
  description = "Key / value list object for configmap data"
}''' >> $DEST/cluster/add-ons/bigbang/infra/variables.tf
#push rendered template to software-factory-testing
cd $DEST
git init
git remote rm origin || true
git remote add origin https://github.com/boozallen/software-factory-testing.git
git checkout -b $PROJECT || true
git add . --all
git commit -a -m' rendered_template - core off , istio on'
git push --set-upstream origin $PROJECT --force
echo "adding in cert-manager"
rm -rf /tmp/cert-manager
git clone https://github.com/boozallen/software-factory-testing.git /tmp/cert-manager
cd /tmp/cert-manager && git checkout ctosc-347
cp -R /tmp/cert-manager/cluster/add-ons/{cert-manager,external-dns,kustomization.yaml} $DEST/cluster/add-ons
cd $DEST
git add . --all
git commit -a -m' added latest for cert-manager, external-dns'
git push --set-upstream origin $PROJECT --force

#deploy rendered template
cd $DEST
terragrunt run-all apply --terragrunt-non-interactive | tee /tmp/$PROJECT-apply.log
export KUBECONFIG=$(readlink -f $(find $DEST/cluster/infra -name "rke2-$PROJECT*.yaml") )
export KEY=$( readlink -f $(find $DEST -name "*.pem" ) )
kubectl get nodes | tee /tmp/$PROJECT.nodes
echo "export KUBECONFIG=$KUBECONFIG" > /tmp/$PROJECT.env
echo "export KEY=$KEY" >> /tmp/$PROJECT.env
kubectl get gitrepositories,kustomizations,hr,po -A | tee $PROJECT.flux
tar --exclude ".terraform" --exclude-vcs --no-mac-metadata -cvzf $ARTIFACTS/$PROJECT-"$(date +%Y-%m-%d_%H-%M-%S)".tgz $DEST /tmp/$PROJECT*
