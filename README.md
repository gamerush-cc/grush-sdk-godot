# GameRush SDK for Godot 4

GameRush の GameAPI を Godot 4 から呼ぶアドオン。ビルドの書き出し方は [対応エンジンと書き出しガイド](https://gamerush.cc/engines)。使い方の正（ランキング・公開プレイヤー状態・投稿が弾かれる条件とエラーコード・API トークン）は [SDK ガイド](https://gamerush.cc/sdk)。

## 導入

`addons/grush_sdk/` をプロジェクトの `addons/` へコピーし、`Project > Project Settings > Plugins` で **GameRush SDK** を有効にする。有効化すると autoload シングルトン `GRush` が自動で登録される。

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

## エディタでの動作確認

Web 書き出し以外では `grush_backend_mock.gd` が使われる。`GRushMock` の static 変数で挙動を切り替える。

```gdscript
GRushMock.signed_in = true
GRushMock.display_name = "Editor Player"
GRushMock.grant_profile_consent = false
GRushMock.unreliable_drop_rate = 0.1

var opponent := GRush.mock_add_peer("Sparring Partner")
opponent.received.connect(func(message: Dictionary) -> void: opponent.send(reply))
```

`GRush.mock_add_peer` で作った相手は同じプロセス内の2人目の peer として部屋に入り、送受信が実際に往復する。

**`unreliable_drop_rate` は既定 0 だが、出荷前に必ず 0 より大きくして試すこと。** WebSocket 中継では `unreliable` も落ちずに届くため、パケットが落ちる前提で書けているかを確認できる場所はエディタのモックだけになる。

## サンプル

`samples/` の `.gd` を、空のシーンのルート `Control` ノードへ付けるだけで動く（シーンファイルは持たない）。

| サンプル | 内容 |
|---|---|
| `samples/score_attack/score_attack.gd` | 疑似IDの取得と表示名の同意要求 |
| `samples/duel/duel.gd` | 2人対戦。エディタではモックの対戦相手が動く |
