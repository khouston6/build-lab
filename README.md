# build-lab

This is a project primarily to better learn Terraform / OpenTofu, Ansible, Cloud-Init, and Azure DevOps.  Everythign is being run on a Windows 11 computer with WSL2 (Ubuntu 22.04) and Proxmox VE 8.2.4.

By no means is anything in here perfect, but I think it works out as a good starting point and I was able to catch some bad practices I was doing.  Make changes and let us see them!



Step 1: Create Cloud-init images for cloning.

Most of this part was borrowed from the wiki: https://pve.proxmox.com/wiki/Cloud-Init_Support

On Proxmox:

- Download the cloud-init images you would like to use.  In my case, I downloaded Almalinux 8 Cloud, Almalinux 9 Cloud, and Fedora 37 Cloud
- Move the qcow2 images to an appropriate images share on your Proxmox machine (They should show up under VM Disks)
- For my images, I created VMs in the following manner:

  - apt install -y libguestfs-tools
  - virt-customize -a [distro].qcow2 --install qemu-guest-agent
  - qemu-img resize [distro].qcow2 32G
  - qm create [VMID] --memory 2048 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single
  - qm set [VMID] --scsi0 [storage]:0,import-from=/path/to/[distro].qcow2
  - qm set [VMID] --ide2 [storage]:cloudinit
  - qm set [VMID] --boot order=scsi0
  - qm set [VMID] --serial0 socket --vga serial0
  - qm template [VMID]
  - repeat for each distro you want to clone

- Be sure you don't set any EFI partitions on the templates, as these are not supported when cloning.


Step 2: Setup accounts on Proxmox for Proxmox provider and others as needed

- This project uses three separate accounts:
    - One is for the provider itself to connect to Proxmox and deploy the VMs (see https://registry.terraform.io/providers/Telmate/proxmox/latest/docs for setup)
    - Another is used exclusively for copying files to the storage where I store my cloud-init / user_data files on Proxmox (you can use root or another Administrator if you choose, just be careful)
    - The last is the user created by cloud-init on each VM.  This will be discussed later.

 
Step 3: Configure Cloud-init file

- The cloud-config file in this repo creates a single new user once your cloud-init image boots up and does not use the default user.  To ensure you can SSH into your machines, change the "ssh_authorized_keys" entry to your own public key.


Step 4: Configure Terraform / OpenTofu files


VARIABLES:

- The files for Terraform are located under the client-machines directory.  The variables for the proxmox provider user and server copy user are defined in variables.tf.  You will need to define the values for these variables in another file with the .tfvars extension.

Example:

#secrets.tfvars
prox_username = "user@pve"
prox_password = "secretpassword"
prox_copy_user = "copy@pve"
prox_copy_key = "/path/to/copy/private/key"
vm_user_key = "/path/to/vm/user/private/key"

- If you wish to use an adminstrative account for the copy (or possibly even the same account used for the provider) you can either reflect your .tfvars file to reflect this or modify the main.tf file.


MAIN.TF:

- This is your main Terraform / OpenTofu file.  Provisioners are defined at the top and are used to add functionality to your script.  Any time you modify these providers, you must run `tofu init` or `terraform init`
- "Locals" is used to create multiple VMs later in the file.  Change these variables as you wish to match your environment.
- The "cloud_init_file_local" and "cloud_init_config" objects are the location of the cloud-config file and it's final destination on the Proxmox server respectively.  In my case, I have a dedicated Proxmox directory named "images" mounted at "/mnt/pve/images".  The script will connect over SSH and copy the cloud-config file to the snippets directory here as "user_data.yml".  If you chose to use a dedicated copy user like I am, be sure you have write permissions to the directory, as well as the Datastore.Allocate permission through the Proxmox GUI / pveum.
- The proxmox_vm_qemu is the resource the defines the actual VMs you are creating.  This depends on the "cloud_init_config" resource having copied the user_data file correctly.
- If you want to use BIOS over UEFI, change the "bios" parameter to "seabios" under the proxmox_vm_qemu resource.
- cicustom points to your user_data file, which should now be on Proxmox.  See the previously listed Cloud-Init_Support page for more information.  Since we are only using a user_data file, use "user=[STORAGE]:snippets/user_data.yml", where [STORAGE] is the name of your storage on Proxmox.
- If you are going with BIOS over UEFI, you can remove the "efidisk" portion of the script.


Step 5: Configure Ansible

- The last part of the main.tf script is specific to Ansible.  We create an inventory.ini file, run the "collect-keys.yaml" script, and run the "disable-cloudinit.yaml" script.

- BIG NOTE:
  The ansible/ansible provider is quite lacking in some areas.  You are unable to define the remote_user from within the main.tf script, so it must instead be set systemwide or in the playbook itself.  If your current user's name is   identical to your new user on the VMs (in this case, user1), then this is not neccessary.
  
  I had to define the "ansible_ssh_private_key_file" directly in the disable-cloudinit.yaml for things to work.

  Forks of the provider exist, but compatibility with the latest version of OpenTofu appears sporadic at best.  Use at your own risk.


INVENTORY.INI
- We need this file in order to properly run Ansible scripts after creation.  The "inventory" resource uses a template file to append IP addresses as they are generated by Terraform / OpenTofu.


COLLECT-KEYS.YAML
- Since we are generating new VMs every time we destroy and apply our main.tf file, the fingerprint for the systems change as well.  If you try to connect to them without first grabbing the new fingerprints, SSH will refuse the connection due to a suspected MITM attack.
- This script will wait 60 seconds to give the VMs a change to boot fully.  After this, it will run ssh-keyscan to grab the new fingerprints and then store them in your known_hosts file.


DISABLE-CLOUDINIT.YAML
- If you reboot your VMs without disabling cloud-init, they will run the cloud-init script on boot each time.  The easiest way to disable this is to create a file at /etc/cloud/cloud-init.disabled
- This is where that third user account comes into play, as you need to use the private SSH key for the public key you defined in your cloud-config file.
- This is a good way to test that your key pair works correctly, but that everything up to this point has worked correctly as well.
- This script will not run until collect-keys.yaml finishes running.


Step 6: Run Terraform / OpenTofu
- From within your client-machines directory, run `tofu init` or `terraform init`.  The providers defined in main.tf will be pulled down and copied locally on your machine.
- Next, run `tofu plan -var-file="/path/to/your/secrets.tfvar"` or `terraform plan -var-file="/path/to/you/secrets.tfvar"`.  If there are any syntax issue with your main.tf, they will likely be caught here.
- If no errors were found, run `tofu apply -var-file="/path/to/you/secrets.tfvar"` or `terraform apply -var-file="/path/to/you/secrets.tfvar"`.  If everything is working correctly, you should see your VMs get created in Proxmox and your Ansible playbooks run.

Congratulations, you just used Terraform to create VMs on Proxmox and configured them with Cloud-init!  Your Ansible playbooks should also have grabbed the new fingerprints and disabled cloud-init.  Going forward, you can use the inventory.ini file to run more playbooks against your VMs.
