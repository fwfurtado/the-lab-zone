mod b2
mod garage


@rclone-check dirname:
    op run --env-file=../../../.env.tpl -- rclone check garage:{{dirname}} b2:the-lab-zone-dr/{{dirname}} --size-only
@rclone-ls rclonePath:
    op run --env-file=../../../.env.tpl -- rclone ls {{rclonePath}}
@rclone-copyto rclonePath localPath:
    op run --env-file=../../../.env.tpl -- rclone copyto {{rclonePath}} {{localPath}}
