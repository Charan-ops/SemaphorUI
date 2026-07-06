# echo "===== DEBUG ====="
# whoami
# echo "HOME=$HOME"
# pwd

# ls -la $HOME
# ls -la $HOME/.aws || true

# cat $HOME/.aws/config || true
# cat $HOME/.aws/credentials || true

# env | grep AWS || true

# aws configure list || true


#!/bin/bash

cd Terraform-files

terraform state list

echo "----------------"

terraform show