# Docker Image Update Checker Action

[![Test](https://github.com/giggio/docker-image-update-checker/actions/workflows/test.yml/badge.svg)](https://github.com/giggio/docker-image-update-checker/actions/workflows/test.yml)
[![GitHub release badge](https://badgen.net/github/release/giggio/docker-image-update-checker/stable)](https://github.com/giggio/docker-image-update-checker/releases/latest)
[![GitHub license badge](https://badgen.net/github/license/giggio/docker-image-update-checker)](https://github.com/giggio/docker-image-update-checker/blob/main/LICENSE)

Action to check if the base image was updated and your image (published on DockerHub) needs to be rebuilt. This action will use Docker's API to compare the base layers of your image with the `base-image`, without the need to pull the images.


## Inputs

| Name         | Type   | Description                                                                                                                  |
| ------------ | ------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `base-image` | String | Base Docker Image                                                                                                            |
| `image`      | String | Your image based on `base-image`                                                                                             |
| `os`         | String | Operating system, necessary if you are using multi arch images and the OS is different from the OS used in the Github action |
| `verbose`    | bool   | Show verbose output                                                                                                          |

Note: the `base-image` needs to have the full path.

If you use a simple image name, like `nginx`, it will be translated to the default Docker Hub library images as `index.docker.io/library/nginx`.
If you use an image with an owner, like `foo/bar`, it will be translated to a Docker Hub images as `index.docker.io/foo/bar`.

The tag is optional, but you could supply it. It will default to `latest`.
You can use it like `index.docker.io/library/nginx:latest` (full name) or `nginx:latest`.

## Output

| Name             | Type   | Description                                               |
| ---------------- | ------ | --------------------------------------------------------- |
| `needs-updating` | String | `true` or `false` if the image needs to be updated or not |


## Example

```yaml
name: check docker images

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
