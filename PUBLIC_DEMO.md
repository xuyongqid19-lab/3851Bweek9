# Public demo

This copy exposes Global Village through one temporary Cloudflare Quick Tunnel URL.
PostgreSQL and Adminer are not routed through the public gateway.

## Start

1. Keep Docker Desktop running.
2. Double-click `StartPublicDemo.cmd`.
3. Wait for the release build to finish and use the displayed `https://...trycloudflare.com` URL.

The script starts Community, Auth, Family, and Chat, builds Flutter Web with the temporary URL, starts the local gateway, and opens the public page.

For Google Sign-In, add the displayed `https://...trycloudflare.com` address to the Web OAuth client's **Authorized JavaScript origins** in Google Cloud. Repeat this whenever the temporary address changes.

## Stop public access

Double-click `StopPublicDemo.cmd`.

This stops the tunnel and gateway but keeps the backend containers and database volumes. Do not use `docker-compose down -v`, because `-v` deletes database data.

## Limitations

- The URL changes each time the public demo is restarted.
- The computer, Docker Desktop, and `cloudflared` process must remain running.
- Password-reset email requires valid `SMTP_USER` and `SMTP_PASS` values in `.env.server`.
- Do not publish `.env.server` or share its secrets.
