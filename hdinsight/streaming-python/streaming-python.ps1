function Start-PythonExample {
    # Script should stop on failures
    $ErrorActionPreference = "Stop"

    # Login to your Azure subscription
    # Is there an active Azure subscription?
    $sub = Get-AzureRmSubscription -ErrorAction SilentlyContinue
    if(-not($sub))
    {
        Add-AzureRmAccount
    }

    # Get cluster info
    $clusterName = Read-Host -Prompt "Enter the HDInsight cluster name"
    # Get the login (HTTPS) credentials for the cluster
    $creds=Get-Credential -Message "Enter the login for the cluster" -UserName "admin"
    $clusterInfo = Get-AzureRmHDInsightCluster -ClusterName $clusterName
    $storageInfo = $clusterInfo.DefaultStorageAccount.split('.')
    $defaultStoreageType = $storageInfo[1]
    $defaultStorageName = $storageInfo[0]

    # Progress indicator
    $activity="Python MapReduce"
    Write-Progress -Activity $activity -Status "Uploading mapper and reducer..."

    # Upload the files
    switch ($defaultStoreageType)
    {
        "blob" {
            # Get the blob storage information for the cluster
            $resourceGroup = $clusterInfo.ResourceGroup
            $storageContainer=$clusterInfo.DefaultStorageContainer
            $storageAccountKey=(Get-AzureRmStorageAccountKey `
                -Name $defaultStorageName `
                -ResourceGroupName $resourceGroup)[0].Value
            # Create a storage context and upload the file
            $context = New-AzureStorageContext `
                -StorageAccountName $defaultStorageName `
                -StorageAccountKey $storageAccountKey
            # Upload the mapper.py file
            Set-AzureStorageBlobContent `
                -File .\mapper.py `
                -Blob "mapper.py" `
                -Container $storageContainer `
                -Context $context
            # Upload the reducer.py file
            Set-AzureStorageBlobContent `
                -File .\reducer.py `
                -Blob "reducer.py" `
                -Container $storageContainer `
                -Context $context `
        }
        "azuredatalakestore" {
            # Get the Data Lake Store name
            # Get the root of the HDInsight cluster azuredatalakestore
            $clusterRoot=$clusterInfo.DefaultStorageRootPath
            # Upload the files. Prepend the destination with the cluster root
            Import-AzureRmDataLakeStoreItem -AccountName $defaultStorageName `
                -Path .\mapper.py `
                -Destination "$clusterRoot/mapper.py" `
                -Force
            Import-AzureRmDataLakeStoreItem -AccountName $defaultStorageName `
                -Path .\reducer.py `
                -Destination "$clusterRoot/reducer.py" `
                -Force
        }
        default {
            Throw "Unknown storage type: $defaultStoreageType"
        }
    }

    # Create the streaming job definition
    # Note: This assumes that the mapper.py and reducer.py
    #       are in the root of default storage. If you put them in a
    #       subdirectory, change the -Files parameter to the correct path.
    $jobDefinition = New-AzureRmHDInsightStreamingMapReduceJobDefinition `
        -Files "/mapper.py", "/reducer.py" `
        -Mapper "mapper.py" `
        -Reducer "reducer.py" `
        -InputPath "/example/data/gutenberg/davinci.txt" `
        -OutputPath "/example/wordcountout"

    # Start the job
    Write-Progress -Activity $activity -Status "Starting the MapReduce job..."
    $job = Start-AzureRmHDInsightJob `
        -ClusterName $clusterName `
        -JobDefinition $jobDefinition `
        -HttpCredential $creds

    # Wait for the job to complete
    Write-Progress -Activity $activity -Status "Waiting for the job to complete..."
    Wait-AzureRmHDInsightJob `
        -JobId $job.JobId `
        -ClusterName $clusterName `
        -HttpCredential $creds

    # Display the results of the job
    Write-Progress -Activity $activity -Status "Downloading job output..."
    switch ($defaultStoreageType)
    {
        "blob" {
            # Get the blob storage information for the cluster
            $resourceGroup = $clusterInfo.ResourceGroup
            $storageContainer=$clusterInfo.DefaultStorageContainer
            $storageAccountKey=(Get-AzureRmStorageAccountKey `
                -Name $defaultStorageName `
                -ResourceGroupName $resourceGroup)[0].Value
            # Create a storage context and download the file
            $context = New-AzureStorageContext `
                -StorageAccountName $defaultStorageName `
                -StorageAccountKey $storageAccountKey
            # Download the file
            Get-AzureStorageBlobContent `
                -Container $storageContainer `
                -Blob "example/wordcountout/part-00000" `
                -Context $context `
                -Destination "./output.txt"
            # Display the output
            Get-Content "./output.txt"
        }
        "azuredatalakestore" {
            # Get the Data Lake Store name
            # Get the root of the HDInsight cluster azuredatalakestore
            $clusterRoot=$clusterInfo.DefaultStorageRootPath
            # Download the file. Prepend the destination with the cluster root
            # NOTE: Unlike getting a blob, this just gets the content and no
            #       file is created locally.
            $sourcePath=$clusterRoot + "example/wordcountout/part-00000"
            Get-AzureRmDataLakeStoreItemContent -Account $defaultStorageName -Path $sourcePath -Confirm
        }
        default {
            Throw "Unknown storage type: $defaultStoreageType"
        }
    }
}

function fix-lineending($original_file) {
    # Set $original_file to the python file path
    $text = [IO.File]::ReadAllText($original_file) -replace "`r`n", "`n"
    [IO.File]::WriteAllText($original_file, $text)
}