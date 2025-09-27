#!/bin/bash
# Test script with shellcheck warnings

echo $1  # SC2086: Double quote to prevent globbing
[ -n $var ]  # SC2086, SC2070
exit
