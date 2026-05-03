import subprocess

DOCKER_DIR = "/opt/docker"

###########################################################################
def add_docker():
    print("Add docker repo")
    try:
        subprocess.run(["dnf", "install", "-y", "dnf-plugins-core"], check=True)
        subprocess.run(["dnf", "config-manager", "--add-repo", "https://download.docker.com/linux/centos/docker-ce.repo"], check=True)
    except Exception as e:
        print("failed to add repo:", e)
        return
###########################################################################
###########################################################################
def install_docker():
    print("This script to install docker on tests VMs")
    try:
        subprocess.run(["dnf", "update", "-y"], check=True)
        subprocess.run(["dnf", "install", "-y", "docker-ce"], check=True)
        output = subprocess.check_output(["docker", "--version"]).decode().strip()
        print("docker version:", output)
    except Exception as e:
        print("install failed:", e)
        return
###########################################################################
###########################################################################
def configure_docker():
    print("Start and Enable Docker Service")
    try:
        subprocess.run(["systemctl", "enable", "docker"], check=True)
        subprocess.run(["systemctl", "start", "docker"], check=True)
    except Exception as e:
        print ("Failed to Start Docker Service", e)
###########################################################################
###########################################################################
def setup_docker_dir():
    try:
        subprocess.run(["mkdir","-p",DOCKER_DIR], check=True)
    except Exception as e:
        print ("failed to create directory", e)
        return
###########################################################################
###########################################################################
def main():
    add_docker()
    install_docker()
    configure_docker()
    setup_docker_dir()
###########################################################################
###########################################################################
if __name__ == "__main__":
    main()