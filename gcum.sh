#!/bin/bash
if [ -z $1 ] || [ -z $2 ] || [ -z $3 ] || [ -z $4 ];
then
    printf "Please include 4 arguments:/n"
    printf "A path to your desired image setup commands,/n"
    printf "A path to your miner startup command,/n"
    printf "A path to a file which lists a server and a number of instances on each line seperated by a space,/n"
    printf "Your project name/n"
    printf "Example: sh gcum.sh setupInstance.txt onInstanceStart.txt asia-servers.txt myProj/n"
    exit
fi

setupScript=$(<$1)
startupScript=$(<$2)
project=$4
id="$RANDOM$RANDOM$RANDOM"
defaultZone="us-west1-b"

echo "Starting project setup..."

#build installer VM
initialVM="initial-vm-$id"
$(gcloud compute --project "$project" instances create "$initialVM" --zone "$defaultZone" --machine-type "n1-standard-1" --subnet "default" --metadata "startup-script=$startupScript,ssh-keys=ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAibPcvoZFX0zfyi2tH4YT7Educw0Sm/r7vNWvkJwGFNI6IBx4C+VOJqkvRCRSSUEU0fKrRcFXrTLLvKzOA0mKJNbCuS8t26W4gxYut3Ac3m5X9Pww82w5jZFcDjPoWVpr9oWa2m2o9PZe7e5AGUFYs0gxXpDUg1+9M1hdNCmK4p+zF2+NguzTbdBebbKjXweogmD/BYRQOECdpsrK+bnl3q4sFFeKqBAFTDYa/79ZEyw9kV7Yj54u8mkwjM7rBAOrBgLGFgeamWxSdEQe3w1tFJ/sFs20pgzYZ4J9CMuGQ0TII9L0fFFi4OwAgYBR9Q+RvIIPRS5w3+uAWVGRNRYOfQ== user" --maintenance-policy "MIGRATE" --scopes default="https://www.googleapis.com/auth/cloud-platform" --image "/ubuntu-os-cloud/ubuntu-1604-xenial-v20161020" --boot-disk-size "10" --boot-disk-type "pd-standard" --boot-disk-device-name "$initialVM")
echo "Spun up instance"
sleep 1m

#Login and setting up reference instance
echo "Setting SSH Key..."
echo -e  'y\n'|ssh-keygen -q -t rsa -N "" -f /home/austin_alltech/.ssh/id_rsa

echo "Logging into SSH and setup..."
$(yes | gcloud compute ssh user@$initialVM --command="$setupScript" --zone "us-west1-b")
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
$(gcloud compute --project "$project" instance-templates create "$instanceTemplate" --machine-type "custom-1-1024" --network "default" --metadata "startup-script=$startupScript,ssh-keys=user:ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAibPcvoZFX0zfyi2tH4YT7Educw0Sm/r7vNWvkJwGFNI6IBx4C+VOJqkvRCRSSUEU0fKrRcFXrTLLvKzOA0mKJNbCuS8t26W4gxYut3Ac3m5X9Pww82w5jZFcDjPoWVpr9oWa2m2o9PZe7e5AGUFYs0gxXpDUg1+9M1hdNCmK4p+zF2+NguzTbdBebbKjXweogmD/BYRQOECdpsrK+bnl3q4sFFeKqBAFTDYa/79ZEyw9kV7Yj54u8mkwjM7rBAOrBgLGFgeamWxSdEQe3w1tFJ/sFs20pgzYZ4J9CMuGQ0TII9L0fFFi4OwAgYBR9Q+RvIIPRS5w3+uAWVGRNRYOfQ== user" --no-restart-on-failure --maintenance-policy "TERMINATE" --preemptible --scopes default="https://www.googleapis.com/auth/cloud-platform" --image "/$project/$image" --boot-disk-size "10" --boot-disk-type "pd-standard" --boot-disk-device-name "$instanceTemplate")

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
