#!/bin/busybox sh
# shellcheck shell=dash

echo "[SP-INSTALLER] init reached (early debug)" >/dev/console 2>/dev/null || true
echo "[SP-INSTALLER] init reached"

exec /bin/sh
