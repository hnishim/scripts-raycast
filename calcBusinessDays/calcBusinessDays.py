#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import datetime
import jpholiday
import argparse
from dateutil.parser import parse, ParserError

# 曜日の日本語表記を定義
WEEKDAYS = ['月', '火', '水', '木', '金', '土', '日']

def format_date_with_weekday(date: datetime.date) -> str:
    """
    日付をYYYY/M/D（曜日）形式の文字列に変換します。
    月と日の先頭の0は表示しません。

    Args:
        date (datetime.date): 変換する日付

    Returns:
        str: YYYY/M/D（曜日）形式の文字列
    """
    return f"{date.year}/{date.month}/{date.day}（{WEEKDAYS[date.weekday()]}）"

# --- Helper Functions ---

def _parse_date_string(date_str: str, arg_name: str = "日付") -> datetime.date:
    """
    日付文字列を解析してdatetime.dateオブジェクトを返します。
    エラーハンドリングも行います。

    Args:
        date_str (str): 解析する日付文字列。
        arg_name (str): エラーメッセージで使用する引数名（例: "開始日", "終了日"）。

    Returns:
        datetime.date: 解析された日付オブジェクト。

    Raises:
        ValueError: 解析に失敗した場合。
    """
    try:
        # dateutil.parserを使って柔軟な形式に対応し、dateオブジェクトを取得
        return parse(date_str).date()
    except ParserError:
        raise ValueError(f"{arg_name}の形式が無効です。YYYY-MM-DD形式などで入力してください。")
    except Exception as e:
        # その他の予期せぬエラー（オーバーフローなど）
        raise ValueError(f"{arg_name}の解析中にエラーが発生しました: {e}")

# --- Public API Functions ---

def count_business_days(start_date_str: str, end_date_str: str) -> int:
    """
    開始日から終了日までの営業日数を計算します（開始日・終了日を含む）。
    jpholiday とセット演算を利用して効率化。

    Args:
        start_date_str (str): 開始日 (YYYY-MM-DD形式など)。
        end_date_str (str): 終了日 (YYYY-MM-DD形式など)。

    Returns:
        int: 期間内の営業日数。

    Raises:
        ValueError: 日付形式が無効な場合、または開始日が終了日より後の場合。
    """
    # ヘルパー関数を使って日付を解析
    start_date = _parse_date_string(start_date_str, "開始日")
    end_date = _parse_date_string(end_date_str, "終了日")

    if start_date > end_date:
        raise ValueError("開始日は終了日以前の日付を指定してください。")

    # --- セット演算ベースのロジック ---
    total_days_count = (end_date - start_date).days + 1
    if total_days_count <= 0:
        return 0

    # 1. 期間内のすべての日付のセットを作成
    all_dates_set = {start_date + datetime.timedelta(days=i) for i in range(total_days_count)}

    # 2. 期間内の祝日のセットを作成 (jpholiday.between を使用)
    holidays_in_period_tuples = jpholiday.between(start_date, end_date)
    holiday_set = {h[0] for h in holidays_in_period_tuples}

    # 3. 期間内の土日のセットを作成
    weekend_set = {d for d in all_dates_set if d.weekday() >= 5}

    # 4. 非営業日のセットを作成 (土日セットと祝日セットの和集合)
    non_business_days_set = weekend_set.union(holiday_set)

    # 5. 期間内に実際に存在する非営業日の数を取得 (all_dates_set との積集合)
    actual_non_business_days_in_period = non_business_days_set.intersection(all_dates_set)

    # 6. 営業日数を計算 (総日数 - 期間内の非営業日の数)
    business_days_count = total_days_count - len(actual_non_business_days_in_period)

    return business_days_count


def find_end_date(start_date_str: str, num_business_days: int) -> datetime.date:
    """
    開始日から指定された営業日数後の日付を計算します。
    jpholiday とセット演算を利用した方法。

    Args:
        start_date_str (str): 開始日 (YYYY-MM-DD形式など)。
        num_business_days (int): 営業日数 (1以上の整数)。

    Returns:
        datetime.date: 計算結果の終了日。

    Raises:
        ValueError: 日付形式が無効、営業日数が無効、または計算結果が見つからない場合。
    """
    # ヘルパー関数を使って開始日を解析
    start_date = _parse_date_string(start_date_str, "開始日")

    if not isinstance(num_business_days, int) or num_business_days < 1:
        # 0営業日後は開始日自身とする場合もあるが、ここでは1以上を要求
        # 1営業日後は、開始日が営業日なら開始日、非営業日なら次の営業日
        raise ValueError("営業日数は1以上の整数で指定してください。")

    # --- セット演算ベースのロジック ---
    # 1. 十分な未来までの期間を推定
    estimated_delta = max(num_business_days + 15, int(num_business_days * 1.5) + 30) # 推定ロジックを調整
    try:
        estimated_end_date = start_date + datetime.timedelta(days=estimated_delta)
    except OverflowError:
        raise ValueError(f"指定された営業日数 ({num_business_days}) が大きすぎるため、終了日を計算できません。")

    # 2. 推定期間内のすべての日付セットを作成 (Set A)
    period_days_count = (estimated_end_date - start_date).days + 1
    all_dates_in_estimation_set = {start_date + datetime.timedelta(days=i) for i in range(period_days_count)}

    # 3. 推定期間内の非営業日セットを作成 (Set B)
    holidays_in_estimation_tuples = jpholiday.between(start_date, estimated_end_date)
    holiday_set_estimation = {h[0] for h in holidays_in_estimation_tuples}
    weekend_set_estimation = {d for d in all_dates_in_estimation_set if d.weekday() >= 5}
    non_business_days_estimation_set = weekend_set_estimation.union(holiday_set_estimation)

    # 4. 推定期間内の営業日セットを作成 (Set C = A - B)
    business_days_estimation_set = all_dates_in_estimation_set.difference(non_business_days_estimation_set)

    # 5. 営業日セットをソート
    sorted_business_days = sorted(list(business_days_estimation_set))

    # 6. N番目の営業日を取得
    if len(sorted_business_days) >= num_business_days:
        final_date = sorted_business_days[num_business_days - 1]
        return final_date
    else:
        raise ValueError(
            f"{num_business_days}営業日後の日付が見つかりませんでした。"
            f"推定した探索期間 ({estimated_delta}日間、終了日: {estimated_end_date.strftime('%Y-%m-%d')}) "
            f"に含まれる営業日が {len(sorted_business_days)}日 しかありませんでした。"
            f"プログラムの推定ロジックを調整するか、入力値を確認してください。"
        )

if __name__ == "__main__":
    # コマンドライン引数のパーサーを作成
    parser = argparse.ArgumentParser(description='日本の祝日(jpholiday利用)を考慮した営業日計算スクリプト。日付はYYYY-MM-DD形式を推奨します。')

    # サブコマンド（モード）の設定
    subparsers = parser.add_subparsers(dest='mode', help='実行モードを選択してください (`count`, `find_date`, `shift_period`)', required=True)

    # モード1: 期間内の営業日数を計算 (count)
    parser_count = subparsers.add_parser('count', help='指定された期間内の営業日数を計算します。')
    parser_count.add_argument('--start', required=True, help='開始日 (例: 2024-05-01)')
    parser_count.add_argument('--end', required=True, help='終了日 (例: 2024-05-10)')

    # モード2: N営業日後の日付を計算 (find_date)
    parser_find = subparsers.add_parser('find_date', help='指定された開始日からN営業日後の日付を計算します。')
    parser_find.add_argument('--start', required=True, help='開始日 (例: 2024-04-26)')
    parser_find.add_argument('--days', required=True, type=int, help='営業日数 (1以上の整数)')

    # モード3: 期間をシフトして新しい終了日を計算 (shift_period)
    parser_shift = subparsers.add_parser('shift_period', help='元の期間の営業日数を計算し、新しい開始日から同じ営業日数後の日付を求めます。')
    parser_shift.add_argument('--original-start', required=True, help='元の期間の開始日')
    parser_shift.add_argument('--original-end', required=True, help='元の期間の終了日')
    parser_shift.add_argument('--new-start', required=True, help='新しい期間の開始日')

    # コマンドライン引数を解析
    args = parser.parse_args()

    try:
        # 選択されたモードに応じて関数を実行
        # --- モード1 の処理 ---
        if args.mode == 'count':
            days = count_business_days(args.start, args.end)
            start_date = _parse_date_string(args.start, "開始日")
            end_date = _parse_date_string(args.end, "終了日")
            print(f"{days} 営業日： {format_date_with_weekday(start_date)} 〜 {format_date_with_weekday(end_date)}")

        # --- モード2 の処理 ---
        elif args.mode == 'find_date':
            end_date = find_end_date(args.start, args.days)
            start_date = _parse_date_string(args.start, "開始日")
            print(f"{format_date_with_weekday(end_date)} ： {format_date_with_weekday(start_date)} の {args.days} 営業日後")

        # --- モード3 の処理 ---
        elif args.mode == 'shift_period':
            # 1. 元の期間の営業日数を計算
            original_business_days = count_business_days(args.original_start, args.original_end)
            if original_business_days < 1:
                orig_start_date = _parse_date_string(args.original_start, "元の開始日")
                orig_end_date = _parse_date_string(args.original_end, "元の終了日")
                print(f"元の期間 ({format_date_with_weekday(orig_start_date)} 〜 {format_date_with_weekday(orig_end_date)}) の営業日数は {original_business_days}日")
                print("営業日数が1未満のため、新しい終了日は計算できません")
            else:
                # 2. 新しい開始日から同じ営業日数後の日付を計算
                new_end_date = find_end_date(args.new_start, original_business_days)
                # 結果表示
                orig_start_date = _parse_date_string(args.original_start, "元の開始日")
                orig_end_date = _parse_date_string(args.original_end, "元の終了日")
                new_start_date = _parse_date_string(args.new_start, "新しい開始日")
                print(f"{format_date_with_weekday(new_end_date)} ： {format_date_with_weekday(new_start_date)} の {original_business_days} 営業日後")

    except (ValueError, OverflowError) as e:
        print(f"エラー: {e}")
    except Exception as e:
        import traceback
        print(f"予期せぬエラーが発生しました: {e}")
        print("--- トレースバック ---")
        traceback.print_exc()
        print("--------------------")