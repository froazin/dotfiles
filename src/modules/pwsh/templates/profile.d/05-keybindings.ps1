# PSReadLine's Windows keys, which already move and delete by word with Ctrl,
# plus what zsh adds: menu completion, editing the line in $EDITOR and help
# for the command under the cursor.

if (Get-Module PSReadLine) {
    Set-PSReadLineOption -EditMode Windows

    # Tab shows every match with its type and description, like zsh's menu
    # select; arrow keys choose.
    Set-PSReadLineKeyHandler -Chord Tab -Function MenuComplete

    # Ctrl+X Ctrl+E: edit the line in $VISUAL or $EDITOR, as in zsh.
    Set-PSReadLineKeyHandler -Chord 'Ctrl+x,Ctrl+e' -Function ViEditVisually

    # Alt+H: help for the command under the cursor, like zsh's run-help.
    Set-PSReadLineKeyHandler -Chord 'Alt+h' -Function ShowCommandHelp
}
