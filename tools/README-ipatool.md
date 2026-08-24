# ipatool

Used only to **enumerate** the external version ids Apple holds for an app. The
install itself happens through the App Store, driven by the AppVersion tweak, so
no `.ipa` is ever downloaded or sideloaded — which is what avoids the FairPlay
problem entirely.

Not committed: it is a 33MB third-party binary. Fetch it with

```bash
mkdir -p tools/bin && cd tools/bin
curl -fsSL -o ipatool.tar.gz \
  https://github.com/majd/ipatool/releases/download/v2.3.2/ipatool-2.3.2-windows-amd64.tar.gz
curl -fsSL -o ipatool.sha256 \
  https://github.com/majd/ipatool/releases/download/v2.3.2/ipatool-2.3.2-windows-amd64.tar.gz.sha256sum
# verify before extracting
tar -xzf ipatool.tar.gz && mv bin/ipatool-*.exe ipatool.exe && rmdir bin
```

sha256 of the v2.3.2 windows-amd64 tarball:
`6352441f6f91df7947aaa203b19cb7d3c9d77920fc466dd784ff9cae88db5c92`

## Usage

`search` and `list-versions` both require an authenticated account, so log in
first. Every command only ever reaches apps the Apple ID can already obtain.

```bash
./ipatool.exe auth login -e you@example.com
./ipatool.exe search uber --limit 5
./ipatool.exe list-versions -b com.ubercab.UberClient
```

Take an id from `list-versions` and enter it in Settings > AppVersion >
Version id on the device.
