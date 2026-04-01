# Test script to verify Azure Storage permissions
# This helps diagnose upload failures

$StorageAccount = "samcpstorage"
$Container = "aztfexport"
$TestFile = "test-upload-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
$TestContent = "Test upload at $(Get-Date)"

Write-Host "`n=== Testing Azure Storage Upload Permissions ===" -ForegroundColor Cyan
Write-Host "Storage Account: $StorageAccount" -ForegroundColor Yellow
Write-Host "Container: $Container" -ForegroundColor Yellow

# Step 1: Check if logged in
Write-Host "`n[Step 1] Checking Azure CLI login..." -ForegroundColor Cyan
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Host "✓ Logged in as: $($account.user.name)" -ForegroundColor Green
    Write-Host "  Subscription: $($account.name) ($($account.id))" -ForegroundColor Gray
} catch {
    Write-Host "✗ Not logged in to Azure CLI" -ForegroundColor Red
    Write-Host "  Run: az login" -ForegroundColor Yellow
    exit 1
}

# Step 2: Check container exists
Write-Host "`n[Step 2] Checking if container exists..." -ForegroundColor Cyan
try {
    $containerCheck = az storage container exists `
        --account-name $StorageAccount `
        --name $Container `
        --auth-mode login `
        2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to check container" -ForegroundColor Red
        Write-Host "  Error: $containerCheck" -ForegroundColor Gray
        Write-Host "`n  Possible causes:" -ForegroundColor Yellow
        Write-Host "  - Storage account '$StorageAccount' does not exist" -ForegroundColor Yellow
        Write-Host "  - Missing role: Storage Blob Data Contributor/Reader" -ForegroundColor Yellow
        Write-Host "  - Network restrictions on storage account" -ForegroundColor Yellow
        exit 1
    }
    
    $exists = ($containerCheck | ConvertFrom-Json).exists
    if ($exists) {
        Write-Host "✓ Container exists: $Container" -ForegroundColor Green
    } else {
        Write-Host "! Container does not exist, will try to create it" -ForegroundColor Yellow
        
        Write-Host "`n[Step 2b] Creating container..." -ForegroundColor Cyan
        $createResult = az storage container create `
            --account-name $StorageAccount `
            --name $Container `
            --auth-mode login `
            2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Container created successfully" -ForegroundColor Green
        } else {
            Write-Host "✗ Failed to create container" -ForegroundColor Red
            Write-Host "  Error: $createResult" -ForegroundColor Gray
            Write-Host "  Missing role: Storage Blob Data Contributor (or Owner)" -ForegroundColor Yellow
            exit 1
        }
    }
} catch {
    Write-Host "✗ Error checking container: $_" -ForegroundColor Red
    exit 1
}

# Step 3: Test upload
Write-Host "`n[Step 3] Testing file upload..." -ForegroundColor Cyan
try {
    # Create a temporary test file
    $tempFile = [System.IO.Path]::GetTempFileName()
    $TestContent | Out-File -FilePath $tempFile -Encoding utf8
    
    $uploadResult = az storage blob upload `
        --account-name $StorageAccount `
        --container-name $Container `
        --name "test/$TestFile" `
        --file $tempFile `
        --auth-mode login `
        --overwrite true `
        2>&1
    
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Successfully uploaded test file" -ForegroundColor Green
        Write-Host "  File: test/$TestFile" -ForegroundColor Gray
    } else {
        Write-Host "✗ Upload failed" -ForegroundColor Red
        Write-Host "  Error: $uploadResult" -ForegroundColor Gray
        Write-Host "`n  Required role assignment:" -ForegroundColor Yellow
        Write-Host "  az role assignment create \" -ForegroundColor Yellow
        Write-Host "    --assignee <your-user-or-sp-id> \" -ForegroundColor Yellow
        Write-Host "    --role 'Storage Blob Data Contributor' \" -ForegroundColor Yellow
        Write-Host "    --scope '/subscriptions/<sub-id>/resourceGroups/rg-mcp-servers/providers/Microsoft.Storage/storageAccounts/$StorageAccount'" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "✗ Upload test failed: $_" -ForegroundColor Red
    exit 1
}

# Step 4: Verify uploaded file
Write-Host "`n[Step 4] Verifying uploaded file..." -ForegroundColor Cyan
try {
    $blobCheck = az storage blob show `
        --account-name $StorageAccount `
        --container-name $Container `
        --name "test/$TestFile" `
        --auth-mode login `
        2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $blob = $blobCheck | ConvertFrom-Json
        Write-Host "✓ File verified in storage" -ForegroundColor Green
        Write-Host "  URL: https://$StorageAccount.blob.core.windows.net/$Container/test/$TestFile" -ForegroundColor Gray
        Write-Host "  Size: $($blob.properties.contentLength) bytes" -ForegroundColor Gray
    } else {
        Write-Host "! Could not verify file, but upload succeeded" -ForegroundColor Yellow
    }
} catch {
    Write-Host "! Verification skipped" -ForegroundColor Yellow
}

# Step 5: Cleanup test file
Write-Host "`n[Step 5] Cleaning up test file..." -ForegroundColor Cyan
try {
    az storage blob delete `
        --account-name $StorageAccount `
        --container-name $Container `
        --name "test/$TestFile" `
        --auth-mode login `
        2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Test file deleted" -ForegroundColor Green
    }
} catch {
    Write-Host "! Cleanup skipped" -ForegroundColor Yellow
}

Write-Host "`n=== ✓ ALL TESTS PASSED ===" -ForegroundColor Green
Write-Host "Your storage permissions are correctly configured!" -ForegroundColor Green
Write-Host ""
