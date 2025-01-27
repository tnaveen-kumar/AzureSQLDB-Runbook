<#
Please note you should create below credentails in the Azure Automation Account
SMTPServerCredential -> This credential will hold the SMPT password
SQLServerCredential -> This will have the password to authenticate to your Azure SQL DB

The Powershell code will fecth the details from the Azure Automation Account and process other details. 

The prams which is mentioned below also can be hardcoded. Optionally if required you could also pass those values at the run time.
#>

param (
    [string]$ServerName="server-name.database.windows.net",   # Azure SQL Server name
    [string]$DatabaseName="DB1", # Database name
    [string]$EmailTo="email@domain.com",      # Recipient email
    [string]$EmailFrom="email@domain.com",    # Sender email
    [string]$SMTPServer="smtp.domain.com"    # SMTP server address
)

$SqlCredential = Get-AutomationPSCredential -Name "SQLServerCredential"
$SqlUserName = $SqlCredential.UserName
$SqlPassword = $SqlCredential.GetNetworkCredential().Password


$SmtpCredential = Get-AutomationPSCredential -Name "SMTPServerCredential"
$SmtpUserName = $SmtpCredential.UserName
$SmtpPassword = $SmtpCredential.GetNetworkCredential().Password

# SQL Connection String
$ConnectionString = "Server=$ServerName;Database=$DatabaseName;User ID=$SqlUserName;Password=$SqlPassword;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

# SQL Query to Identify Blocking Sessions
$BlockingQuery = @"
SELECT 
    r.blocking_session_id AS BlockingSessionID,
    r.session_id AS BlockedSessionID,
    r.wait_time / 1000 AS WaitTimeSeconds, -- Convert wait time from milliseconds to seconds
    r.wait_type AS WaitType,
    r.last_wait_type AS LastWaitType,
    t.text AS BlockingQuery,
    DB_NAME(r.database_id) AS DatabaseName,
    r.start_time AS StartTime,
    r.command AS Command,
    r.status AS Status,
    s.login_name AS LoginName,
    s.host_name AS HostName
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
WHERE r.blocking_session_id <> 0  -- Filter to get only the blocked sessions
ORDER BY r.wait_time DESC; -- Order by the longest wait time first
"@

try {
    Write-Output "Connecting to database..."
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $ConnectionString
    $SqlConnection.Open()

    $SqlCommand = $SqlConnection.CreateCommand()
    $SqlCommand.CommandText = $BlockingQuery
    $SqlDataReader = $SqlCommand.ExecuteReader()

    # Convert Results to DataTable
    $DataTable = New-Object System.Data.DataTable
    $DataTable.Load($SqlDataReader)
    $SqlConnection.Close()

    # Check for Blocking Sessions
    if ($DataTable.Rows.Count -gt 0) {
        Write-Output "Blocking sessions detected. Preparing report..."

        # Generate HTML Report
        $HtmlReport = "<h1>Blocking Sessions Report for Azure SQL Database</h1>"
        $HtmlReport += "<table border='1' cellpadding='5' cellspacing='0'>"
        $HtmlReport += "<tr><th>BlockingSessionID</th><th>BlockedSessionID</th><th>WaitTimeSeconds</th><th>WaitType</th><th>BlockingQuery</th><th>DatabaseName</th><th>StartTime</th><th>Command</th><th>Status</th><th>LoginName</th><th>HostName</th></tr>"

        foreach ($Row in $DataTable.Rows) {
            $HtmlReport += "<tr>"
            $HtmlReport += "<td>$($Row.BlockingSessionID)</td>"
            $HtmlReport += "<td>$($Row.BlockedSessionID)</td>"
            $HtmlReport += "<td>$($Row.WaitTimeSeconds)</td>"
            $HtmlReport += "<td>$($Row.WaitType)</td>"
            $HtmlReport += "<td>$($Row.BlockingQuery)</td>"
            $HtmlReport += "<td>$($Row.DatabaseName)</td>"
            $HtmlReport += "<td>$($Row.StartTime)</td>"
            $HtmlReport += "<td>$($Row.Command)</td>"
            $HtmlReport += "<td>$($Row.Status)</td>"
            $HtmlReport += "<td>$($Row.LoginName)</td>"
            $HtmlReport += "<td>$($Row.HostName)</td>"
            $HtmlReport += "</tr>"
        }
        $HtmlReport += "</table>"


        Write-Output "Sending email..."
        $Message = New-Object Net.Mail.MailMessage
        $Message.From = $EmailFrom
        $Message.To.Add($EmailTo)
        $Message.Subject = "Azure SQL DB Blocking Sessions Report"
        $Message.Body = $HtmlReport
        $Message.IsBodyHtml = $true

        $SMTP = New-Object Net.Mail.SmtpClient($SMTPServer, 587)
        $SMTP.EnableSsl = $true
        $SMTP.Credentials = New-Object System.Net.NetworkCredential($SmtpUserName, $SmtpPassword)
        $SMTP.Send($Message)

        Write-Output "Email sent successfully!"
    } else {
        Write-Output "No blocking sessions detected."
    }
} catch {
    Write-Error "An error occurred: $_"
}
