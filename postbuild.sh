#!/bin/bash
# Vercel post-build hook - copies download files to web output
echo "🤖 Chat Aski v1.0.0 - post-build hook"
cp chat-aski.apk build/web/ 2>/dev/null || echo "⚠️ no apk yet"
cp ChatAski.mobileconfig build/web/ || echo "✅ mobilecopied"
cp download.html build/web/ || echo "✅ downloadcopied"
