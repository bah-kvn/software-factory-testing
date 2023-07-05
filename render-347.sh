#!/bin/bash -e
export AMI="ami-08b68a787bb9cf0f3"      # CIS RHEL 7 STIG AMI
export BASE=$PWD
export PROJECT="ctosc-97"
export SOURCE_BRANCH="main"
export ACCOUNT=$(echo $AWS_DEFAULT_PROFILE | cut -d '-' -f2)
echo "Project = $PROJECT"
export DEST=$HOME/factory/$PROJECT #change this to the directory the code to live
export ARTIFACTS=$HOME/factory/artifacts #change this to the directory the code to live
export DOMAIN="$PROJECT.bsf-testing.com"
export AGE_KEY_FILE="$HOME/.ssh/default.age" #file is read to get the AGE public and private keys
export PUBLIC_KEY="$( cat $AGE_KEY_FILE | grep public | cut -d ' ' -f4 )"
export PRIVATE_KEY="$( cat $AGE_KEY_FILE | grep -v "^#" )"
export SOPS_AGE_KEY="$PRIVATE_KEY"
rm -rf /tmp/ctosc-347
git clone https://github.com/boozallen/software-factory.git /tmp/ctosc-347
cd /tmp/ctosc-347 && git checkout ctosc-347

#render the template
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
  -d assume_role="arn:aws:iam::$ACCOUNT:role/TerraformDeployer" \
  -d cert=false \
  -d perm_boundaries=true \
  -d perm_boundary_needed=true \
  -d email="dev@bah.com" \
  -d hosted_zone_id="Z05620741ABABDDEC0B4Z" \
  -d iam_users_perm_boundary="arn:aws:iam::$ACCOUNT:policy/BAH_User_Policy_Boundary" \
  --overwrite  $PWD /tmp/rendered
