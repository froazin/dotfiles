# Inline suggestions from history and completion, like zsh-autosuggestions in
# 90-plugins.zsh. Right arrow or End accepts one.

if (Get-Module PSReadLine) {
    $esc = [char]27
    # PSReadLine refuses predictions when the console can't show them, such as
    # when output is redirected, so each try fails quietly.
    try {
        # HistoryAndPlugin needs PowerShell 7.2 and PSReadLine 2.2; splatted,
        # since 5.1 and 7.0 have neither parameter.
        $options = @{ PredictionSource = 'HistoryAndPlugin'; PredictionViewStyle = 'InlineView'; ErrorAction = 'Stop' }
        Set-PSReadLineOption @options
    } catch {
        try {
            $options = @{ PredictionSource = 'History'; ErrorAction = 'Stop' }
            Set-PSReadLineOption @options
        } catch {
            $null = $_
        }
    }
    # The prompt's dim grey.
    Set-PSReadLineOption -Colors @{ InlinePrediction = "$esc[38;2;106;106;106m" }
    Remove-Variable -Name esc, options -ErrorAction SilentlyContinue
}
