# Auto-Retry GitLab CI

## About

### Problem

Tests are failing due to a remote GitLab server issue.

### Temporary solution

If you know your tests pass locally, then run this script after submitting a PR
to ensure that jobs get restarted automatically after remote failures.

This script will check all your branches every 2 minutes to ensure the latest
pipelines are passing. It will automatically retry any failing jobs.

## Setup

1. Open your `~/.bash_profile` in an editor.
2. Set the `GITLAB_BASE_URL` environment variable with your GitLab base URL:

        export GITLAB_BASE_URL=https://gitlab.example.com

3. Set the `GITLAB_TOKEN` environment variable with a GitLab personal access token (**Profile --> Access Tokens**):

        export GITLAB_TOKEN=abcdefghij123456789

4. Save your `~/.bash_profile` and exit the editor.

5. Open a new Terminal window to let changes to take effect, or run:

        source ~/.bash_profile

6. Make scripts executable:

        chmod ug+x auto_retry_gitlab_ci.rb auto_retry_gitlab_ci.sh

## Running the scripts

### Main script

Running the main script will run the process in the foreground, so the Terminal window must remain open.

#### To run main script:

````
./auto_retry_gitlab_ci.rb
````

Or if you're not currently in the script directory:

```
/path/to/auto_retry_gitlab_ci.rb
````

#### To stop:

The script will stop automatically once all pipelines are passing, but to force stop it, press:

````
Ctrl-C
````

You can also close the Terminal window that is currently running the script.

### Shell wrapper script [preferred]

Running the shell wrapper script will run the main script as a background process, so there is no need to keep Terminal open.

#### To run shell script:

````
./auto_retry_gitlab_ci.sh
````

Or if you're not currently in the script directory:

```
/path/to/auto_retry_gitlab_ci.sh
````

#### To stop:

The script will stop automatically once all pipelines are passing, but to force stop it, first find the PID of the process running it. List all processes:

````
ps
````

You'll see something like:

````
50242 ttys007    0:00.08 -bash
50309 ttys007    0:00.22 irb
54117 ttys008    0:00.24 -bash
54629 ttys008    0:00.11 ruby /path/to/auto_retry_gitlab_ci/auto_retry_gitlab_ci.rb
````

Find the correct PID belonging to the script, and kill the process:

````
kill 54629
````

## Log

Log messages are written to `/tmp/auto_retry_gitlab_ci.log`. To see the last 10 lines of the log:

````
tail /tmp/auto_retry_gitlab_ci.log
````

To see the last 20 lines:

````
tail -20 /tmp/auto_retry_gitlab_ci.log
````

To automatically refresh the last 20 lines of the log:

````
tail -f -20 /tmp/auto_retry_gitlab_ci.log
````

## Reminding to run the script

You can add a git hook to your repo to remind you to run the script after each time you run `git push`. Copy the `git_hooks_pre_push.sample` file to your git repo:

````
cp git_hooks_pre_push.sample /path/to/your/repo/.git/hooks/pre-push
````

You will get the following message after every `git push`:

````
To auto-retry, run:"
  ~/Developer/scripts/auto_retry_gitlab_ci/auto_retry_gitlab_ci.sh
````

If this is not where your script is actually located, you can edit the file to print the correct script path.

## Other notes

- Only one instance of the script will ever be allowed to run. Once the script starts, a lock file called `/tmp/auto_retry_gitlab_ci.lock` is created to ensure no other instances can run. This file gets deleted once the script stops running (whether or it stopped gracefully or forcefully).
- Pipelines / jobs with status `manual` are paused and requests to retry via the API seemingly  get ignored. This requires actually visiting the GitLab website and clicking on the "Retry" button manually to force continue.
