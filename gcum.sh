#!/bin/bash
if [ -z $1 ] || [ -z $2 ] || [ -z $3 ] || [ -z $4 ] || [ -z $5 ] || [ -z $6 ] || [ -z $7 ];
then
    printf "Please include 7 arguments:/n"
    printf "A path to your desired image setup commands,/n"
    printf "A path to your miner startup command,/n"
    printf "A path to a file which lists a server and a number of instances on each line seperated by a space,/n"
    printf "A path to the open SSH pubkey you will use for instances/n"
    printf "The name of the image you would like to use. default: /ubuntu-os-cloud/ubuntu-1604-xenial-v20161020"
    printf "Your desired project zone ex: us-west1-b
    printf "Your gcloud project name/n"
    printf "Example: sh gcum.sh setupInstance.txt onInstanceStart.txt asia-servers.txt projPubKey/path.file /ubuntu-os-cloud/ubuntu-1604-xenial-v20161020 us-west1-b myProj /n"
    exit
fi

setupScript=$(<$1)
startupScript=$(<$2)
sshKeys=$(<$4)
project=$7
id="$RANDOM$RANDOM$RANDOM"
defaultZone=$6
username=$(whoami)

echo "Starting project setup..."

#build installer VM
initialVM="initial-vm-$id"
$(gcloud compute --project "$project" instances create "$initialVM" --zone "$defaultZone" --machine-type "n1-standard-1" --subnet "default" --metadata "startup-script=$startupScript,ssh-keys=$sshKeys" --maintenance-policy "MIGRATE" --scopes default="https://www.googleapis.com/auth/cloud-platform" --image "/ubuntu-os-cloud/ubuntu-1604-xenial-v20161020" --boot-disk-size "10" --boot-disk-type "pd-standard" --boot-disk-device-name "$initialVM")
echo "Spun up instance"
sleep 1m

#Login and setting up reference instance
echo "Setting SSH Key..."
echo -e  'y\n'|ssh-keygen -q -t rsa -N "" -f /home/$username/.ssh/id_rsa

echo "Logging into SSH and setup..."
$(yes | gcloud compute ssh user@$initialVM --command="$setupScript" --zone "$defaultZone")
sleep 2m

#Create snapshot
echo "Creating snapshot"
$(gcloud compute --project "$project" disks snapshot "$initialVM" --zone "$defaultZone" --snapshot-names "snapshot-$id")

#Create disk
echo "Creating disk"
disk="disk-$id"
$(gcloud compute --project "$project" disks create "disk-$id" --size "10" --zone "$defaultZone" --source-snapshot "snapshot-$id" --type "pd-standard")

echo "Creating image"
#create image
image="image-$id"
$(gcloud compute --project "$project" images create "$image" --source-disk "$disk" --source-disk-zone "$defaultZone")

echo "Creating template"
#create instance template
instanceTemplate="instance-template-$id"
$(gcloud compute --project "$project" instance-templates create "$instanceTemplate" --machine-type "custom-1-1024" --network "default" --metadata "startup-script=$startupScript,ssh-keys=$sshKeys" --no-restart-on-failure --maintenance-policy "TERMINATE" --preemptible --scopes default="https://www.googleapis.com/auth/cloud-platform" --image "/$project/$image" --boot-disk-size "10" --boot-disk-type "pd-standard" --boot-disk-device-name "$instanceTemplate")

echo "Deleting setup VM"
delete initial VM
$(yes | gcloud compute instances delete $initialVM --zone "$defaultZone")

echo "Launching group instance"
#launch group instances
while IFS=' ' read -r -a line || [[ -n "$line" ]]; do
    serverName=${line[0]}
    numSpawn=${line[1]}
    instanceName="$project-$serverName-$numSpawn"
    echo "Launching group instance $instanceName"
    $(gcloud compute --project "$project" instance-groups managed create "$instanceName" --zone "$serverName" --base-instance-name "$instanceName" --template "$instanceTemplate" --size "$numSpawn")
done < "$3"

echo "Complete!"
