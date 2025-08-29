#!/bin/bash

# 🎯 SmartScene WWDC 2025 部署脚本

echo "🚀 开始部署 SmartScene WWDC 2025 应用..."

# 检查设备连接
echo "📱 检查设备连接..."
xcrun devicectl list devices

# 编译项目
echo "🔨 编译项目..."
xcodebuild -project "ml-fastvlm/app/FastVLM.xcodeproj" \
           -scheme "FastVLM App" \
           -configuration Debug \
           -destination 'id=00008110-001905C83C86401E' \
           -allowProvisioningUpdates build

if [ $? -eq 0 ]; then
    echo "✅ 编译成功！"
    
    # 安装到设备
    echo "📲 安装到设备..."
    APP_PATH=$(ls -d ~/Library/Developer/Xcode/DerivedData/FastVLM-*/Build/Products/Debug-iphoneos/FastVLM\ App.app 2>/dev/null | head -n 1)
    xcrun devicectl device install app --device 00008110-001905C83C86401E "$APP_PATH"
    
    # 启动应用
    echo "🎮 启动应用..."
    xcrun devicectl device process launch --device 00008110-001905C83C86401E com.jiajunwu.FastVLM.DRM95Z373U
    
    echo "🎉 部署完成！应用已启动"
else
    echo "❌ 编译失败，请检查错误信息"
    exit 1
fi
