# build-lab

This is a project primarily to better learn Terraform / OpenTofu, Ansible, and Azure DevOps.  Everythign is being run on a Windows 11 computer with WSL2 (Ubuntu 22.04) and Proxmox VE 8.2.4.

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

- Be sure you don't set any EFI partitions on the templates, as these are not supported when cloning.

On OpenTofu:

- BIG NOTE: The ansible/ansible provider is quite lacking and made it so I had to hard code some variables in the plays themselves.  For some reason, they don't let you define
  the remote_user / ansible_user or the ansible.cfg file, so it will default to your environmental variables.  There are other forks, but they seemed to crash when I tried to use them on
  the latest version of OpenTofu.
