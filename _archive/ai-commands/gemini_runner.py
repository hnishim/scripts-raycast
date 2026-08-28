#!/usr/bin/python3
import sys
from gemini_client import GeminiError, generate_content, render_prompt


def main():
    prompt_file, model, input_source, temp_dir = sys.argv[1:]
    try:
        with open(prompt_file, encoding="utf-8") as stream:
            template = stream.read()
        input_path = temp_dir + ("/input" if input_source == "stdin" else "/clipboard")
        with open(input_path, encoding="utf-8") as stream:
            selection = stream.read()
        prompt = render_prompt(template, selection)
        with open(temp_dir + "/response", "w", encoding="utf-8") as output:
            output.write(generate_content(prompt, model))
    except (OSError, UnicodeError):
        print("入力またはプロンプトを読み込めません。", file=sys.stderr)
        return 1
    except GeminiError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
