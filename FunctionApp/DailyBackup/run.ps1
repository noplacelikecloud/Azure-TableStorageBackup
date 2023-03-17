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

    #Authorizize with Azure
    Write-Debug "Connect to Azure Account with managed identity"
    Connect-AzAccount -Identity

    # Get the Storage Account Context
    try {
        #Get Context
        Write-Debug "Get Context of Storage Accounts..."
        $StorageAccountContext = (Get-AzStorageAccount -Name $StorageAccountNameSource -ResourceGroupName $RGNameSource).Context
        $FileShareSAContext = (Get-AzStorageAccount -Name $StorageAccountNameTarget -ResourceGroupName $RGNameTarget).Context

        #Iterate through all the tables in the storage account -> Folder level in File Share
        $Tables = Get-AzStorageTable -Context $StorageAccountContext
    } catch {
        Write-Error -Message "Failed to get source storage account. Check if permissions are correct: $_"
    }

    foreach ($Table in $Tables)
    {
        $TableName = $Table.Name

        #Check if File Share exists
        $TableFileShare = Get-AzStorageShare -Name $TableName.ToLower() -Context $FileShareSAContext
        
        if (!$TableFileShare) {
            Write-Debug "Creating Backup-FileShare $TableFileShare ..."
            #Create File Share
            New-AzRmStorageShare -ResourceGroupName $RGNameTarget -StorageAccountName $StorageAccountNameTarget -Name $TableName.ToLower() -AccessTier Cool
        } else {
            Write-Debug "Backup-FileShare $TableFileShare already exists! Continue..."
        }

        # Create Folder for Table if not exists
        Write-Debug "Check if folder $TableName exists..."

        $targetFolder = Get-Item -Path $env:TEMP/$TableName -ErrorAction Ignore
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
            $PartitionData = Get-AzTableRow -Table $CloudTable -PartitionKey $Partition -ErrorAction Ignore
            #Convert the data to JSON and write to a file in temp folder
            $PartitionData | ConvertTo-Json | Out-File -FilePath "$env:TEMP\$TableName\$($Partition).json"
        }
    }

    Write-Debug "Starting upload to backup account"
    foreach ($table in $Tables) {
        $tableName = $table.Name
        # Upload to file share
        $CurrentFolder = (Get-Item $env:TEMP/$tableName).FullName
        $Container = Get-AzStorageShare -Name $tableName.ToLower() -Context $FileShareSAContext
        Get-ChildItem -Path $env:TEMP/$tableName -Recurse | Where-Object { $_.GetType().Name -eq "FileInfo"} | ForEach-Object {
            $path=$_.FullName.Substring($CurrentFolder.Length+1).Replace("\","/")
            Write-Output "Upload Partition $($_.FullName) from table $tableName"
            Set-AzStorageFileContent -Sharename $Container.Name -Context $FileShareSAContext -Source $_.FullName -Path $path -Force
        }
    }
    Write-Output -Message "Completed!"
}