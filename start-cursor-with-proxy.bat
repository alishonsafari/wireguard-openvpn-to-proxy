@echo off
set HTTP_PROXY=http://127.0.0.1:2080
set HTTPS_PROXY=http://127.0.0.1:2080
start "" "%LOCALAPPDATA%\Programs\Cursor\Cursor.exe" --disable-http2
