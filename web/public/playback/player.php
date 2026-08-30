<?php
http_response_code(410);
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Playback proxy retired</title>
  <style>
    body { margin: 0; font-family: ui-sans-serif, system-ui, sans-serif; background: #0a0a0d; color: #fafafa; }
    main { min-height: 100vh; display: grid; place-items: center; padding: 24px; text-align: center; }
    p { max-width: 28rem; line-height: 1.5; color: #a1a1aa; }
    a { color: #fff; }
  </style>
</head>
<body>
  <main>
    <div>
      <h1>Playback proxy retired</h1>
      <p>Same-origin HLS proxy is unavailable on this host. Open Watch from Fotty — streams play in the provider embed.</p>
      <p><a href="/">Back to Fotty</a></p>
    </div>
  </main>
</body>
</html>
