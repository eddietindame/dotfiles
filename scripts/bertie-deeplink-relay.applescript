-- Relay bertie-dev:// deep links to the mac mini, where the dev app runs.
--
-- The desktop app registers its protocol on whichever machine it runs on. With
-- the app on the mini and the browser here, macOS resolves bertie-dev:// locally
-- and the link never reaches the app. This owns the scheme here and forwards it.
--
-- launchctl asuser is required on the far side: a plain `ssh mini open ...`
-- lands outside the console GUI session, where it cannot reach a window server.

on open location this_URL
	set remoteCommand to "launchctl asuser $(id -u) open " & quoted form of this_URL
	try
		do shell script "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 mini " & quoted form of remoteCommand
	on error errMsg
		display notification errMsg with title "Bertie deep link relay failed"
	end try
end open location
