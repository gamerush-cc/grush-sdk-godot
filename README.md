# GameRush SDK for Godot 4

GameRush の GameAPI を Godot 4 から呼ぶアドオン。ビルドの書き出し方は [対応エンジンと書き出しガイド](https://gamerush.cc/engines)。使い方の正（ランキング・公開プレイヤー状態・投稿が弾かれる条件とエラーコード・API トークン）は [SDK ガイド](https://gamerush.cc/sdk)。

## 導入

[リリース](https://github.com/gamerush-cc/grush-sdk-godot/releases)から版（例: `v1.2.0`）を選んで取得し、`addons/grush_sdk/` をプロジェクトの `addons/` へコピーし、`Project > Project Settings > Plugins` で **GameRush SDK** を有効にする。有効化すると autoload シングルトン `GRush` が自動で登録される。

書き出しは Web。それ以外のプラットフォームでは自動的にモックへ落ちる。

## 使い方

```gdscript
var self_result: Dictionary = await GRush.player.get_self()
if self_result["ok"]:
    print(self_result["value"]["pseudo_id"])

var joined: Dictionary = await GRush.net.join("duel")
if joined["ok"]:
    var room: GRushRoom = joined["value"]
    room.message_received.connect(func(message: Dictionary) -> void: print(message["from"]))
    room.send(payload, GRush.CHANNEL_UNRELIABLE, GRush.EVERYONE)
```

すべての API は `{"ok": bool, "value": Variant, "code": String, "message": String}` を返し、例外を投げない。GameRush の外で動かした場合は `ok` が `false`、`code` が `"unsupported"` になるだけで、ゲームは止まらない。

### 共有

```gdscript
if await GRush.share.is_available():
    var shared: Dictionary = await GRush.share.share_screen("ステージ3をクリア")
```

GameRush の確認シートが出て、プレイヤーが送り先を押したときに共有が開く。`value` は `{"status": "opened"}` か `{"status": "cancelled"}` だけ。`share` の画像は PNG にして base64 で渡す。`share_screen` はゲームの canvas のスクショを送る。自前の画像を送るなら `share(text, image)`（`Image`）。共有は 5 秒に 1 回までなので、1 回のボタン操作で呼ぶのはどちらか一方にする。共有したことを条件に報酬を出さない。本文は 100 文字までで、URL と @メンションを含むと `invalidParams`。古い GameRush（`protocolVersion` 3 未満）では `unsupported`。

### 表示言語

```gdscript
var fetched: Dictionary = await GRush.locale.fetch()
if fetched["ok"]:
    print(fetched["value"]["locale"])
GRush.locale.changed.connect(func(next: Dictionary) -> void: print(next["locale"]))
```

GameRush 本体の表示言語を読む。`value` は `{"locale": "ja-JP", "source": "user", "languages": PackedStringArray}`。`source` は `"user"`（プレイヤーが選んだ）・`"system"`（アプリの端末設定）・`"device"`（ブラウザの言語）のどれか。`GRush.locale.current()` は取得済みなら同じ Dictionary、まだなら `null` を返す。表示言語が決まったとき・変わったときに `changed` が発火する（JS の呼び出しの中ではなく `call_deferred` で後から配る）。古い GameRush（`protocolVersion` 4 未満）では `fetch` が `unsupported`、`current` が `null`。

## エディタでの動作確認

Web 書き出し以外では `grush_backend_mock.gd` が使われる。`GRushMock` の static 変数で挙動を切り替える。

```gdscript
GRushMock.signed_in = true
GRushMock.display_name = "Editor Player"
GRushMock.grant_profile_consent = false
GRushMock.unreliable_drop_rate = 0.1
GRushMock.share_status = "cancelled"

var opponent := GRush.mock_add_peer("Sparring Partner")
opponent.received.connect(func(message: Dictionary) -> void: opponent.send(reply))
```

`GRush.mock_add_peer` で作った相手は同じプロセス内の2人目の peer として部屋に入り、送受信が実際に往復する。

表示言語のモックは `GRushMock.locale`（例 `"en-US"`、`source` は `"user"`）を返し、空なら `OS.get_locale()` を BCP47 に直して `source: "device"` で返す。

共有のモックは確認シートを出さず、`GRushMock.share_status`（既定 `"opened"`）を返す。`GRushMock.share_available = false` で共有できない環境を試せる。本文と画像の検査はしない。

**`unreliable_drop_rate` は既定 0 だが、出荷前に必ず 0 より大きくして試すこと。** WebSocket 中継では `unreliable` も落ちずに届くため、パケットが落ちる前提で書けているかを確認できる場所はエディタのモックだけになる。

## GameRush 向けの書き出し（任意）

`addons/grush_sdk_build/` は、GameRush 向けの推奨設定で Web 書き出しをするための別アドオン。使う場合は `addons/` へコピーし、`Project > Project Settings > Plugins` で **GameRush SDK Build** を **GameRush SDK とは別に**有効にする。Godot 4.3 以降と、Web 用の書き出しテンプレート（`Editor > Manage Export Templates`）が必要。

`export_presets.cfg` に **「GameRush Web」** という名前のプリセットを作り、既にあれば推奨値へ書き戻す（ほかのプリセットには触れない）。スレッドは無効（GameRush の配信は COOP/COEP ヘッダを送らない）、スマホ向けテクスチャ圧縮（ETC2/ASTC）は既定で有効、`addons/grush_sdk_build/*` は書き出しから除外される。書き出し先がプロジェクト内なら、その親フォルダ（既定では `build/`）に `.gdignore` を置いて取り込み対象から外す（親フォルダにほかのファイルがあるときは置かずに警告する）。プロジェクト直下のフォルダには書き出せない。

エディタでは `Project > Tools` の2項目から使う。

| メニュー | 内容 |
|---|---|
| `GameRush: 書き出し設定を確認` | 「GameRush Web」の現在値と推奨値を並べて表示し、「推奨を適用」でプリセットだけを書き換える |
| `GameRush: 推奨設定で書き出す` | 書き出し先を選び、プリセットを推奨値にしてから書き出し、サイズと警告を表示する |

エクスポートダイアログを開いたまま使った場合は、閉じて開き直すと新しいプリセットが見える（エディタはプリセットをメモリに持っている）。書き出し中はエディタが固まったように見える。

コマンドラインからも同じことができる（CI 向け）。

```sh
godot --headless --path . --script res://addons/grush_sdk_build/grush_build_cli.gd -- --output build/gamerush
```

`--no-mobile-textures` でスマホ向けテクスチャ圧縮を外し、`--preset-only` でプリセットだけ書いて書き出しを省く。出力は `[grush-build] ` で始まる行で、変更した設定は `set <key>: <旧> -> <新>` と出る。

| 終了コード | 意味 |
|---|---|
| 0 | 成功（目安の 15MB を超えたときは警告だけ出る。30MB 以上は危険） |
| 1 | 書き出し失敗（多くは書き出しテンプレートの未インストール） |
| 2 | 引数・Godot のバージョン・書き出し先（プロジェクト直下、`addons/`、`.godot/`）が不正 |
| 4 | GameRush のアップロード上限（2000 ファイル / 50MB）を超えた |

## サンプル

`samples/` の `.gd` を、空のシーンのルート `Control` ノードへ付けるだけで動く（シーンファイルは持たない）。

| サンプル | 内容 |
|---|---|
| `samples/score_attack/score_attack.gd` | 疑似IDの取得と表示名の同意要求 |
| `samples/duel/duel.gd` | 2人対戦。エディタではモックの対戦相手が動く |
