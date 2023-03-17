# Azure Table Storage Backup

As Microsoft doesn't provide a native way to backup table storages in Storage Accounts I've decided to code an Azure Function to provide this functionality.

### Functionality

The function will call your storage account and iterate through all tables in it and will create a file share for each table on the target storage account.

Every partition key inside the table will be catched and converted to a JSON file.

After finishing, the target backup file share will contain JSON-Files with your table storage data, which can be:
* snapshotted
* backed up to a Recovery Services Vault (in Preview)

### Deployment

Feel free to use the Deploy the Azure Button below :)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fnoplacelikecloud%2FAzure-TableStorageBackup%2Fmaster%2FBicepTemplates%2FDeployFunction_forDeployToAzureButton.json)

### Installation

TBD
