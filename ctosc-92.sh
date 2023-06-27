#!/bin/bash -e
export AMI="ami-08b68a787bb9cf0f3"      # CIS RHEL 7 STIG AMI
export BASE=$PWD
export PROJECT="$(basename -s '.sh' $(readlink -f $0))"

export SOURCE_BRANCH="$PROJECT"
export DEST=$HOME/factory/$PROJECT #change this to the directory the code to live
export ARTIFACTS=$HOME/factory/artifacts #change this to the directory the code to live
export DOMAIN="$PROJECT.bsf-testing.com"
export AGE_KEY_FILE="$HOME/.ssh/default.age" #file is read to get the AGE public and private keys
export PUBLIC_KEY="$( cat $AGE_KEY_FILE | grep public | cut -d ' ' -f4 )"
export PRIVATE_KEY="$( cat $AGE_KEY_FILE | grep -v "^#" )"
export SOPS_AGE_KEY="$PRIVATE_KEY"
echo "Project = $PROJECT  |  $DOMAIN"
echo """
git clone https://github.com/boozallen/software-factory $DEST-source
kustomization="$DEST-source/blueprints/rke-single-cluster/cluster/add-ons/bigbang/kustomization.yaml.jinja"
yq e ".resources[0] = \"https://repo1.dso.mil/big-bang/bigbang//base?ref=2.4.1\"" -i $kustomization
cat $kustomization
cd $DEST-source
git checkout -b $PROJECT
git add . --all
git commit -a -m' updates before rendering '
git push --set-upstream origin $PROJECT --force

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
  -d git_repo="https://github.com/boozallen/software-factory-testing.git" \
  -d git_branch="$PROJECT" \
  -d git_user="$GH_USERNAME" \
  -d git_pat="$GH_PASSWORD" \
  -d dev_environment="staging" \
  -d should_assume_role=true \
  -d assume_role="arn:aws:iam::721762329763:role/TerraformDeployer" \
  -d cert=false \
  -d perm_boundaries=true \
  -d email="dev@bah.com" \
  -d hosted_zone_id="Z05620741ABABDDEC0B4Z" \
  -d iam_users_perm_boundary="arn:aws:iam::721762329763:policy/BAH_User_Policy_Boundary" \
  --overwrite \
  -r "$SOURCE_BRANCH" \
  gh:boozallen/software-factory $DEST

cd $DEST
git init
git remote add origin https://github.com/boozallen/software-factory-testing.git
git checkout -b $PROJECT
git add . --all
git commit -a -m' rendered_template '
git push --set-upstream origin $PROJECT --force
"""
cd $DEST && git init && terragrunt run-all apply --terragrunt-non-interactive | tee /tmp/$PROJECT-apply.log
export KUBECONFIG=$( readlink -f $(find $DEST/cluster/infra -name "rke2-$PROJECT*.yaml") )
export KEY=$( readlink -f $(find $DEST -name "*.pem" ) )
kubectl get nodes | tee /tmp/$PROJECT-nodes.log
echo "export KUBECONFIG=$KUBECONFIG" > /tmp/$PROJECT.env
echo "export KEY=$KEY" >> /tmp/$PROJECT.env
kubectl get gitrepositories,kustomizations,hr,po -A | tee /tmp/$PROJECT.log
kubectl get -n bigbang helmrelease.helm.toolkit.fluxcd.io/neuvector -o yaml | tee -a /tmp/$PROJECT.log
tar --exclude ".terraform" --exclude-vcs --no-mac-metadata -cvzf $ARTIFACTS/$PROJECT-"$(date +%Y-%m-%d_%H-%M-%S)".tgz $DEST /tmp/$PROJECT*

