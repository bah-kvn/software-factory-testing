#!/bin/bash -e
export AMI="ami-08b68a787bb9cf0f3"      # CIS RHEL 7 STIG AMI
export BASE=$PWD
export PROJECT="ctosc-94-prsf73"
export ACCOUNT=$(echo $AWS_DEFAULT_PROFILE | cut -d '-' -f2)
echo "Project = $PROJECT"
export DEST=$HOME/factory/$PROJECT #change this to the directory the code to live
export ARTIFACTS=$HOME/factory/artifacts #change this to the directory the code to live
export DOMAIN="bsf-testing.com"
export AGE_KEY_FILE="$HOME/.ssh/default.age" #file is read to get the AGE public and private keys
export PUBLIC_KEY="$( cat $AGE_KEY_FILE | grep public | cut -d ' ' -f4 )"
export PRIVATE_KEY="$( cat $AGE_KEY_FILE | grep -v "^#" )"
export SOPS_AGE_KEY="$PRIVATE_KEY"

#clone main then checkout the pr and push to a branch 
git clone https://github.com/boozallen/software-factory $DEST-source
cd $DEST-source
gh pr checkout 73
git checkout -b $PROJECT
git push --set-upstream origin $PROJECT --force

#render the template from the pr branch 
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
  --overwrite \
  -r "$PROJECT" \
  gh:boozallen/software-factory $DEST

#push rendered template to software-factory-testing
cd $DEST
git init
git remote add origin https://github.com/boozallen/software-factory-testing.git
git checkout -b $PROJECT
git add . --all
git commit -a -m' rendered_template '
git push --set-upstream origin $PROJECT --force

#deploy rendered template
cd $DEST
git init && terragrunt run-all apply --terragrunt-non-interactive | tee /tmp/$PROJECT-apply.log
export KUBECONFIG=$(find $DEST/cluster/infra -name "rke2-$PROJECT*.yaml")
export KEY=$( readlink -f $(find $DEST -name "*.pem" ) )
kubectl get nodes | tee /tmp/$PROJECT.nodes
echo "export KUBECONFIG=$KUBECONFIG" > /tmp/$PROJECT.env
echo "export KEY=$KEY" >> /tmp/$PROJECT.env
kubectl get gitrepositories,kustomizations,hr,po -A | tee $PROJECT.flux
tar --exclude ".terraform" --exclude-vcs --no-mac-metadata -cvzf $ARTIFACTS/$PROJECT-"$(date +%Y-%m-%d_%H-%M-%S)".tgz $DEST /tmp/$PROJECT*
