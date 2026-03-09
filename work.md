cd C:\Users\saeed\workspaces\scripts\translate
powershell -ExecutionPolicy Bypass -File .\scripts\switch-wireguard-profile.ps1 -ProfilePath .\profiles\VS7.conf -RestartStack

docker compose up -d --force-recreate gluetun xray
docker compose ps