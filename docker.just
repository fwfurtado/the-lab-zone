repository := "ofwfurtado"


[arg('app-name', long="app-name")]
[arg('tag', long="tag")]
@build-and-push app-name tag="latest":
    cd "docker/{{app-name}}" && docker build -t "{{repository}}/{{app-name}}:{{tag}}" .
    docker push "{{repository}}/{{app-name}}:{{tag}}"
    crane digest "{{repository}}/{{app-name}}:{{tag}}"
