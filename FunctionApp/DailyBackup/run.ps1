<#
.SYNOPSIS
  Backup Azure Table Storage via Azure Functions App
.DESCRIPTION
  This script will backup all tables and partitions from a given Azure Table Storage Account to another Azure Table Storage Account as JSON files.
.PARAMETER None
    No parameters are required
.NOTES
  Version:        1.0
  Author:         Bernhard Fluer
  Creation Date:  17.03.2023
  Purpose/Change: Initial script development
#>
#Requires -Version 5.0
#Requires -Modules AzTable, Az.Storage

param($Timer)

# Only run the backup when the timer trigger fires
if ($Timer) {
    # Parameters 
    $StorageAccountNameSource = $env:StorageAccountNameSource
    $StorageAccountNameTarget = $env:StorageAccountNameTarget
    $RGNameSource = $env:RGNameSource
    $RGNameTarget = $env:RGNameTarget

    # Welcome Message + Info about Params
    Write-Host "Welcome to the Table Storage Backup Script!"
    Write-Host "Your data will be grabbed from $StorageAccountNameSource and backup to $StorageAccountNameTarget"

    # Import the Azure Storage Module
    Import-Module Az.Storage
    Import-Module AzTable

    # Get the Storage Account Context
    try {
        #Get Context
        Write-Debug "Get Context of Storage Accounts..."
        $StorageAccountContext = (Get-AzStorageAccount -Name $StorageAccountNameSource -ResourceGroupName $RGNameSource).Context
        $FileShareSAContext = (Get-AzStorageAccount -Name $StorageAccountNameTarget -ResourceGroupName $RGNameTarget).Context

        Get-AzStorageAccount -Name $StorageAccountNameTarget -ResourceGroupName $RGNameSource | Out-Null

        #Iterate through all the tables in the storage account -> Folder level in File Share
        $Tables = Get-AzStorageTable -Context $StorageAccountContext
    } catch {
        Write-Error -Message "Failed to get storage accounts. Check if storage account names and permissions are correct: $_"
    }

    #Check if File Share exists
    $TableFileShare = Get-AzStorageShare -Name "backup$StorageAccountNameSource" -Context $FileShareSAContext -ErrorAction SilentlyContinue
        
    if (!$TableFileShare) {
        Write-Debug "Creating Backup-FileShare..."
        #Create File Share
        New-AzRmStorageShare -ResourceGroupName $RGNameTarget -StorageAccountName $StorageAccountNameTarget -Name "backup$StorageAccountNameSource" -AccessTier Cool
    } else {
        Write-Debug "Backup-FileShare already exists! Continue..."
    }

    foreach ($Table in $Tables)
    {
        $TableName = $Table.Name    

        # Create Folder for Table if not exists
        Write-Debug "Check if folder $TableName exists..."

        $targetFolder = Get-Item -Path $env:TEMP/$TableName -ErrorAction SilentlyContinue
        if(!$targetFolder) {
            Write-Debug "Creating folder $TableName ..."
            $targetFolder = New-Item -Name $TableName -ItemType Directory -Path $env:TEMP
        } else {
            Write-Debug "Folder $TableName exists! Continue ..."
        }
        #Iterate through all the partitions in the table -> File level in File Share
        Write-Debug "Getting PartitionKeys of Table $TableName"
        $CloudTable = (Get-AzStorageTable -Context $StorageAccountContext -Name $TableName).CloudTable
        $Partitions = (Get-AzTableRow -Table $CloudTable -SelectColumn "PartitionKey").PartitionKey | Select-Object -Unique
        
        Write-Debug "Write to JSON Files"
        foreach ($Partition in $Partitions)
        {
            #Get the data for the partition
            $PartitionData = Get-AzTableRow -Table $CloudTable -PartitionKey $Partition -ErrorAction SilentlyContinue
            #Convert the data to JSON and write to a file in temp folder
            $PartitionData | ConvertTo-Json | Out-File -FilePath "$env:TEMP\$TableName\$($Partition).json"
        }
    }

    Write-Debug "Starting upload to backup account"
    foreach ($table in $Tables) {
        $tableName = $table.Name
        # Create Folder for Table on File Share if not exists
        $folder = Get-AzStorageFile -ShareName "backup$StorageAccountNameSource" -Context $FileShareSAContext -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq $tableName.ToLower()}
        if (!$folder) {
            New-AzStorageDirectory -ShareName "backup$StorageAccountNameSource" -Context $FileShareSAContext -Path $tableName.ToLower()
        } else {
            Write-Debug "Folder $tableName exists on File Share! Continue ..."
        }
    }
    
    # Remove old folders
    $share = Get-AzStorageFile -ShareName "backup$StorageAccountNameSource" -Context $FileShareSAContext | Where-Object {$_.Type -eq "Directory"}
    foreach ($dir in $share) {
        if ($Tables -contains $dir.Name) {
            continue
        } else {
            Write-Debug "Remove old folder $dir.Name"
        }
        $dir | Remove-AzStorageFile -Force
    }

    foreach ($table in $Tables) {
        $tableName = $table.Name
        # Upload to file share
        $CurrentFolder = (Get-Item $env:TEMP/$tableName).FullName
        $Container = Get-AzStorageShare -Name "backup$StorageAccountNameSource" -Context $FileShareSAContext
        Get-ChildItem -Path $env:TEMP/$tableName -Recurse | Where-Object { $_.GetType().Name -eq "FileInfo"} | ForEach-Object {
            $path="$tableName/$($_.FullName.Substring($CurrentFolder.Length+1).Replace("\","/"))"
            Write-Output "Upload Partition $($_.FullName) from table $tableName"
            Set-AzStorageFileContent -Sharename $Container.Name -Context $FileShareSAContext -Source $_.FullName -Path $path -Force
        }
    }
    Write-Output -Message "Completed!"
}