#!/bin/bash -e
export PROJECT="istio-01"
export DEST=$HOME/factory/$PROJECT
export DOMAIN="$PROJECT.bsf-testing.com"
export AGE_KEY_FILE="$HOME/.ssh/default.age"

# Shouldn't require updates below this line ( assuming you have the env vars listed in the cmds below set )
export ARTIFACTS=$HOME/factory/artifacts/$PROJECT
export PUBLIC_KEY="$( cat $AGE_KEY_FILE | grep public | cut -d ' ' -f4 )"
export PRIVATE_KEY="$( cat $AGE_KEY_FILE | grep -v "^#" )"
mkdir -p $(dirname $DEST) $ARTIFACTS $(dirname $ARTIFACTS)/zips
cp $(readlink -f $0) $ARTIFACTS
echo """skipping
copier \
  -d age_key_file="$AGE_KEY_FILE" \
  -d age_secret_key="$PRIVATE_KEY" \
  -d age_public_key="$PUBLIC_KEY" \
  -d aws_region="us-east-1" \
  -d aws_ami="ami-08b68a787bb9cf0f3" \
  -d blueprint="rke-single-cluster" \
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
  -r "$PROJECT" \
  gh:boozallen/software-factory $DEST
"""
cd $DEST
git init
git remote add origin https://github.com/boozallen/software-factory-testing.git
git checkout -b $PROJECT
git add . --all
git commit -a -m' rendered_template '
git push --set-upstream origin $PROJECT --force

cd $DEST && terragrunt run-all apply --terragrunt-non-interactive | tee $ARTIFACTS/apply.log
echo; echo;
export KUBECONFIG=$( readlink -f $(find $DEST/cluster/infra -name "rke2-$PROJECT*.yaml") )
export KEY=$( readlink -f $(find . -name "$PROJECT.pem" -print0 | xargs -r -0 ls -1 -t | head -1 ) )
echo "export KEY=$KEY" > $ARTIFACTS/$PROJECT.env
echo "export KUBECONFIG=$KUBECONFIG" >> $ARTIFACTS/$PROJECT.env
unset KUBECONFIG && source $ARTIFACTS/$PROJECT.env
echo; echo;
kubectl get nodes | tee $ARTIFACTS/nodes
env > $ARTIFACTS/deploy.env
tar --exclude ".terraform" --exclude-vcs --no-mac-metadata -cvzf $( dirname $ARTIFACTS)/zips/$PROJECT_"$(date +%Y-%m-%d_%H-%M-%S)".tgz $ARTIFACTS $DEST

