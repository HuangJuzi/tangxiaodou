#!/usr/bin/env python3
"""
Sophnet TTS Script
Supports text-to-speech generation using Sophnet TTS API.
"""
import os
import sys
import argparse
import json
import tempfile
import requests
from typing import Optional, Dict, Any
import sophnet_tools

GENERATE_URL = "https://www.sophnet.com/api/open-apis/projects/easyllms/voice/synthesize-audio"

def create_request(
    text: Optional[str],
    voice: Optional[str] = "longyumi_v2",
    speech_rate: Optional[float] = 1.0
) -> dict:
    """Build request body for TTS generation."""
    payload = {
        "text": [
            text,
        ],
        "synthesis_param": {
            "model": "cosyvoice-v2",
            "voice": voice,
            "format": "MP3_16000HZ_MONO_128KBPS",
            "volume": 80,
            "speechRate": speech_rate,
            "pitchRate": 1
        }
    }
    return payload

def gen_tts(
    api_key: str, text: str, voice: str = "longyingxiao", speech_rate: float = 1.0
) -> Dict[str, Any]:
    """Make HTTP request with authentication."""
    clean_text = (text or "").strip()
    if not clean_text:
        return {"error": "文本不能为空"}

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    temp_file_path: Optional[str] = None
    try:
        response = requests.post(
            GENERATE_URL,
            headers=headers,
            json=create_request(clean_text, voice, speech_rate),
            timeout=60
        )
        if response.status_code != 200:
            return {
                "error": (
                    f"HTTP请求失败，状态码: {response.status_code}, 响应内容: {response.text}"
                )
            }

        with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp:
            temp_file_path = tmp.name
            f = tmp
            f.write(response.content)

        result = sophnet_tools.upload_oss(temp_file_path, timeout=120)
        if result:
            return {"audio_url": result}

        return {"error": "音频上传失败"}
    except requests.exceptions.RequestException as e:
        return {"error": f"HTTP请求失败: {e}"}
    finally:
        if temp_file_path and os.path.exists(temp_file_path):
            os.remove(temp_file_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sophnet TTS Script")
    parser.add_argument("--text", required=True, help="Text to generate audio")
    parser.add_argument("--voice", type=str, default="优雅知性女", help="Voice name. Defaults to 优雅知性女")
    parser.add_argument("--speech-rate", type=float, default=1.0, help="Speech rate. Defaults to 1.0")
    args = parser.parse_args()
    voice_dict = {
                    "清甜推销女": "longyingxiao",
                    "呆萌机器人": "longjiqi", 
                    "经典猴哥":"longhouge", 
                    "毒舌心机女":"longjixin", 
                    "欢脱粤语男":"longanyue", 
                    "原味陕北男":"longshange", 
                    "甜美闽南女":"longanmin", 
                    "娇率才女音":"longdaiyu", 
                    "得道高僧":"longgaoseng", 
                    "利落从容女":"longanli", 
                    "清爽利落男": "longanlang", 
                    "优雅知性女":"longanwen", 
                    "居家暖男":"longanyun", 
                    "正经青年女":"longyumi_v2", 
                    "知性积极女": "longxiaochun_v2", 
                    "沉稳权威女声":"longxiaoxia_v2",
                    "沉稳青年男": "longshu_v2", 
                    "精准干练女": "loongbella_v2", 
                    "博才干练男":"longshuo_v2", 
                    "沉稳播报女":"longxiaobai_v2", 
                    "典型播音女":"longjing_v2",
                }
    api_key = sophnet_tools.get_api_key()
    if api_key is None:
       print(f"❌ 未找到 Sophnet API Key，请联系客户支持")
       sys.exit(1)
    
    selected_voice = voice_dict.get(args.voice, voice_dict["优雅知性女"])
    result = gen_tts(
        api_key,
        args.text,
        voice_dict.get(selected_voice, voice_dict["优雅知性女"]),
        args.speech_rate,
    )

    if "audio_url" in result:
        print(f"🎙️ 声音风格: {selected_voice}")
        print(f"📝 播报内容: {args.text}")
        print(f"🎵 生成音频: ![audio]({result['audio_url']})")
    else:
        print(f"❌ 音频生成失败: {result.get('error', '音频生成失败')}")
        sys.exit(1)
