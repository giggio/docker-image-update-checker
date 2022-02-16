# Registry Image Update Checker Action

[![Test](https://github.com/giggio/docker-image-update-checker/actions/workflows/test.yml/badge.svg)](https://github.com/giggio/docker-image-update-checker/actions/workflows/test.yml)
[![GitHub release badge](https://badgen.net/github/release/giggio/docker-image-update-checker/stable)](https://github.com/giggio/docker-image-update-checker/releases/latest)
[![GitHub license badge](https://badgen.net/github/license/giggio/docker-image-update-checker)](https://github.com/giggio/docker-image-update-checker/blob/main/LICENSE)

Action to check if the base image was updated and your image (published on DockerHub or other registry) needs to be rebuilt.
This action will use the registry's API to compare the base layers of your image with the `base-image`, without the need to pull the images.


## Inputs

| Name         | Type   | Description                      | Required | Default value          |
| ------------ | ------ | -------------------------------- | -------- | ---------------------- |
| `base-image` | String | Base Docker Image                | true     |                        |
| `image`      | String | Your image based on `base-image` | true     |                        |
| `os`         | String | Operating system                 | false    | GH action OS           |
| `arch`       | String | System architecture              | false    | GH action architecture |
| `verbose`    | bool   | Show verbose output              | false    | false                  |

**Note:** `os` and `arch` are necessary if you are checking multiarch images and their OS and/or
system architecture are different from the one used in the Github action.

If you use a simple image name, like `nginx`, it will be translated to the default Docker Hub library images as `index.docker.io/library/nginx`.
If you use an image with an owner, like `foo/bar`, it will be translated to a Docker Hub images as `index.docker.io/foo/bar`.

The tag is optional, but you could supply it. It will default to `latest`.
You can use it like `index.docker.io/library/nginx:latest` (full name) or `nginx:latest`.

## Output

| Name             | Type   | Description                                               |
| ---------------- | ------ | --------------------------------------------------------- |
| `needs-updating` | String | `true` or `false` if the image needs to be updated or not |


## Examples

### Simple update check

This is the only function of this action:

```yaml
name: Check outdated images

on:
  schedule:
    - cron:  '0 4 * * *'

jobs:
  docker:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v2
      - name: Check if update available
        id: check
        uses: giggio/docker-image-update-checker@v2
        with:
          base-image: library/nginx:1.21.0
          image: user/app:latest
          os: linux # optional
          verbose: true # optional
      - name: Build and push
        uses: docker/build-push-action@v2
        with:
          context: .
          push: true
          tags: user/app:latest
        if: steps.check.outputs.needs-updating == 'true'
```

### Build and update

This action both builds and also checks for an update.
Notice the `step.if` condition:

```yaml
name: Build image

on:
  schedule:
    - cron:  '0 4 * * *'
  workflow_dispatch:
  push:
    branches:
      - main
    tags:
      - "*"
    paths-ignore:
      - "**.md"
  pull_request:
    branches:
      - main
    paths-ignore:
      - "**.md"

jobs:
  docker:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v2
      - name: Check if update available
        id: check
        uses: giggio/docker-image-update-checker@v2
        with:
          base-image: library/nginx:1.21.0
          image: user/app:latest
      - name: Build and push
        uses: docker/build-push-action@v2
        with:
          context: .
          push: true
          tags: user/app:latest
        if: success() && (contains(fromJson('["push", "pull_request"]'), github.event_name) || (steps.check.outputs.needs-updating == 'true' && github.event_name == 'schedule'))
```

### Windows example

```yaml
# rest of the file omitted
      - name: Check if update available
        id: check
        uses: giggio/docker-image-update-checker@v2
        with:
          base-image: mcr.microsoft.com/windows/servercore:ltsc2022
          image: user/app
          os: windows
```

[See other examples](https://github.com/giggio/docker-image-update-checker/blob/main/.github/workflows/test.yml)
and their
[runs](https://github.com/giggio/docker-image-update-checker/actions/workflows/test.yml)
in this repo.