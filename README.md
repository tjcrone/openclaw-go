# OpenClaw Go
Scripts to make OpenClaw go on GCP.

## Steps
0. Edit `settings.conf` to set your username and other settings.
1. Create a new project on GCP.
2. Use gcloud CLI to authenticate to your new project.
3. Run `setup_project.sh` to setup your GCP project.
4. Run `create_instance.sh` to create a VM.
5. Log in to VM.
6. Run `install_openclaw.sh` on the VM to install OpenClaw.
7. Run `configure_openclaw.sh` to setup the models and agents.

