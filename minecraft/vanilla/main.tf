terraform {
    required_providers {
        coder = {
            source = "coder/coder"
            version = ">= 2.10.0"
        }
        docker = {
            source = "kreuzwerker/docker"
            version = ">= 3.6.2"
        }
    }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
    os            = "linux"
    arch          = "amd64"
    dir           = "/workspace"
    api_key_scope = "all"
    display_apps {
        vscode          = true
        vscode_insiders = false
        web_terminal    = true
        ssh_helper      = false
    }

    metadata {
        display_name = "CPU Usage"
        key          = "cpu_usage"
        script       = "coder stat cpu"
        interval     = 10
        timeout      = 1
        order        = 2
    }
    metadata {
        display_name = "RAM Usage"
        key          = "ram_usage"
        script       = "coder stat mem"
        interval     = 10
        timeout      = 1
        order        = 1
    }

    order = 1
}

resource "coder_script" "minecraft" {
    agent_id = coder_agent.main.id
    display_name = "Minecraft"
    icon = "https://www.svgrepo.com/download/349453/minecraft.svg"
    run_on_start = true
    script = <<-EOF
        #!/bin/sh
        /start
    EOF
}

resource "coder_app" "minecraft" {
    agent_id = coder_agent.main.id
    display_name = "Minecraft"
    icon = "https://www.svgrepo.com/download/349453/minecraft.svg"
    slug         = "minecraft"
    url = "tcp://localhost:25565"
    share = "public"
    subdomain = true
}

resource "docker_container" "ubuntu" {
    count = data.coder_workspace.me.start_count
    image = "itzg/minecraft-server"
    name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
    hostname = data.coder_workspace.me.name
    # Use the docker gateway if the access URL is 127.0.0.1
    entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
    env        = [
        "CODER_AGENT_TOKEN=${coder_agent.main.token}",
        "EULA=TRUE"
    ]
    host {
        host = "host.docker.internal"
        ip   = "host-gateway"
    }
    ports {
        internal = 25565
        external = 25565
        ip = "0.0.0.0"
        protocol = "tcp"
    }
    # volumes {
    #     container_path = "/home/coder"
    #     volume_name    = docker_volume.home_volume.name
    #     read_only      = false
    # }
}