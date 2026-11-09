/// アプリ招待メッセージの組み立て。
/// 純関数として切り出してテストできるようにしている。
/// リリース後は URL をストアの配布ページ（Google Play / App Store）に差し替え、
/// 招待コード（?ref=userId）を付けて、招待経由の登録で両者を繋げる予定（v2）。
const String kAppUrl =
    'https://github.com/daichiyabunaka-rgb/Meshitomo-app-prototype';

String inviteText(String nickname) {
  return '一緒に「めしとも」を使いませんか？\n'
      '趣味でつながる飯とも探しアプリ。顔ではなく中身で、'
      '近くの人と今からご飯に行けるよ。\n'
      '$nicknameも参加しています。一般利用は完全無料です。\n'
      '$kAppUrl';
}

/// 特定の募集に誘う共有文（「この募集に参加しませんか」でも SNS 共有できる）
String recruitmentShareText(String title, String meetup) {
  return '一緒に飯に行きませんか？「めしとも」で募集しています。\n'
      '「$title」（集合: $meetup）\n'
      '$kAppUrl';
}
