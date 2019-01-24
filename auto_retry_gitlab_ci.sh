#!/bin/sh

# Shell wrapper for auto_retry_ci_pipeline.rb

script="/Users/SEphraim/Developer/scripts/auto_retry_ci_pipeline/auto_retry_ci_pipeline.rb"
nohup "$script" &>/dev/null &
