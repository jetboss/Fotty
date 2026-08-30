<?php
http_response_code(410);
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
echo json_encode([
  'error' => 'Playback media proxy retired on this host.',
  'code' => 'playback_proxy_retired',
]);
