mod b2
mod garage


rclone-check dirname:
    op run --env-file=../../../.env.tpl -- rclone check garage:{{dirname}} b2:the-lab-zone-dr/{{dirname}} --size-only
