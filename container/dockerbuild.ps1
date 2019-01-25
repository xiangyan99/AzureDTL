param (
    [switch] $reset,
    [switch] $attach,
    [switch] $push,
    [string] $Command
)

function Write-HostHeader () {
    param( [string] $Title )
    Write-Host "================================================================="
    Write-Host "= $Title"
    Write-Host "================================================================="
}

Clear-Host
$containerImage = "xiangyan99/devtestlab-ansible"

$containers = $(docker ps -a -q -f ancestor=$($containerImage))
if ($containers) { 

    Write-HostHeader -Title "Deleting container instances"    
    docker rm -f $containers 
}

if ($reset) { 
    
    Write-HostHeader -Title "Deleting container images"
    docker image rm -f $($containerImage) 
}

Write-HostHeader -Title "Building container image"
docker build -t $($containerImage) .

if ($push) {

    Write-HostHeader -Title "Pushing container to registry"
    docker push $($containerImage)
}

if ($attach) {

    Write-HostHeader -Title "Start & Attach container $containerImage"
    docker run -it $($containerImage) $Command

} else {

    Write-HostHeader -Title "Start & Detach container $containerImage"
    docker run -d $($containerImage)
}
