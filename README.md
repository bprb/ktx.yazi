Clone this to `<yazi config>/plugins/ktx.yazi`,
then add to `yazi.toml`:


```
[plugin]
prepend_previewers = [
    { name = "*.ktx", run = 'ktx' },
]
```

