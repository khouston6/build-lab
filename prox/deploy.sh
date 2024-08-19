#!/bin/bash

cd client-machines

tofu init

tofu plan -var-file="secrets.tfvars" # change this to match the location and name of your .tfvars file

read -n 2 -p "Continue with Apply?  Enter "y" to continue, "n" to quit. " userinput
case $userinput in
  y|Y) tofu apply -var-file="secrets.tfvars" ;; # change this to match the location and name of your .tfvars file
  *) printf " \n Exiting \n" && exit 1
esac

cd ../ansible

ansible-playbook -i inventory.ini collect-keys.yaml
ansible-playbook -i inventory.ini disable-cloudinit.yaml