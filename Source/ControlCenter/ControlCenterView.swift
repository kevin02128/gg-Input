// Copyright © 2026 wtf. All rights reserved.
// ControlCenterView.swift — gg 控制台精簡版介面（狀態顯示、模型開關、解除安裝）

import SwiftUI

public struct ControlCenterView: View {
    @ObservedObject var manager: ControlCenterManager
    @State private var showUninstallAlert = false
    @State private var deleteUserDataOnUninstall = false
    @State private var hasAgreedToLicense = true
    @State private var showLicenseModal = false

    public init(manager: ControlCenterManager) {
        self.manager = manager
    }

    public var body: some View {
        Group {
            if manager.imeState == .notInstalled {
                installWizardView
            } else {
                standardDashboardView
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 500)
        .sheet(isPresented: $showLicenseModal) {
            licenseModalSheet
        }
    }

    // MARK: - 尚未安裝時：安裝引導精靈

    private var installWizardView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("gg 輸入法")
                        .font(.system(size: 20, weight: .bold))
                    Text("WTF Co., Ltd. 開發")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("軟體授權合約與隱私權聲明")
                    .font(.system(size: 13, weight: .semibold))

                ScrollView {
                    Text(LicenseText.content)
                        .font(.system(size: 11))
                        .lineSpacing(4)
                        .foregroundColor(.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Toggle(isOn: $hasAgreedToLicense) {
                    Text("我已詳細閱讀並同意接受上述「軟體授權合約」與「隱私權政策」")
                        .font(.system(size: 12))
                }

                if !manager.installProgressMessage.isEmpty {
                    HStack(spacing: 8) {
                        if manager.isInstalling {
                            ProgressView().controlSize(.small)
                        }
                        Text(manager.installProgressMessage)
                            .font(.system(size: 12, weight: .medium))
                    }
                }

                HStack(spacing: 16) {
                    Button("前往系統鍵盤設定") {
                        manager.openKeyboardSettings()
                    }
                    .buttonStyle(.link)

                    Spacer()

                    Button(action: {
                        manager.installOrUpgradeIME()
                    }) {
                        Text("同意並安裝 gg 輸入法")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasAgreedToLicense || manager.isInstalling)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 已安裝時：單頁精簡控制台（狀態、模型開關、解除安裝）

    private var standardDashboardView: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. 狀態區塊
                    GroupBox(label: Text("系統運作狀態").font(.system(size: 13, weight: .bold))) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Circle()
                                    .fill(manager.imeState.isRunning ? Color.green : Color.red)
                                    .frame(width: 10, height: 10)
                                Text(manager.imeState.displayText)
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text("版本：\(manager.installedVersion)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            HStack {
                                Text("安裝路徑：")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(manager.imeAppPath)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        .padding(10)
                    }

                    // 2. 開關模型區塊
                    GroupBox(label: Text("Kyon 智慧選字模型").font(.system(size: 13, weight: .bold))) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: manager.hasValidModel ? $manager.wtfContextCorrection : .constant(false)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("啟用 Kyon")
                                        .font(.system(size: 14, weight: .semibold))

                                }
                            }
                            .disabled(!manager.hasValidModel)

                            if !manager.hasValidModel {
                                Button("開啟模型放置目錄") {
                                    manager.openModelsFolder()
                                }
                                .font(.system(size: 12))
                            }

                            Divider()

                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                GridRow {
                                    Text("引擎狀態：")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(!manager.hasValidModel ? "未安裝模型" : (manager.wtfContextCorrection ? "啟用中" : "已停用"))
                                        .font(.system(size: 12, weight: .medium))
                                }
                                GridRow {
                                    Text("累積審查次數：")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text("\(manager.neuralTotalInferences) 次")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                                GridRow {
                                    Text("最近審查延遲：")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(manager.neuralLastLatencyMs > 0 ? String(format: "%.2f ms", manager.neuralLastLatencyMs) : "待命")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                            }
                        }
                        .padding(10)
                    }

                    // 3. 解除安裝區塊
                    GroupBox(label: Text("解除安裝").font(.system(size: 13, weight: .bold))) {
                        HStack(alignment: .center, spacing: 12) {
                            Toggle(isOn: $deleteUserDataOnUninstall) {
                                Text("同時清除個人詞庫與學習紀錄 (~/Library/Application Support/gg)")
                                    .font(.system(size: 12))
                            }
                            Spacer()
                            Button(role: .destructive, action: {
                                showUninstallAlert = true
                            }) {
                                Text("解除安裝")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.red)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(manager.isBusy)
                        }
                        .padding(10)
                    }

                    if !manager.maintenanceMessage.isEmpty {
                        Text(manager.maintenanceMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("確定解除安裝嗎？", isPresented: $showUninstallAlert) {
            Button("取消", role: .cancel) { }
            Button("解除安裝", role: .destructive) {
                manager.uninstallIME(deleteUserData: deleteUserDataOnUninstall)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(.accentColor)

            Text("gg 輸入法控制台")
                .font(.system(size: 16, weight: .bold))

            Spacer()

            Button("授權條款") {
                showLicenseModal = true
            }
            .buttonStyle(.link)
            .font(.system(size: 12))

            Button("重啟輸入法") {
                manager.restartIME()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(manager.isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var licenseModalSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("gg 輸入法 軟體授權合約與隱私權政策")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("關閉") {
                    showLicenseModal = false
                }
                .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                Text(LicenseText.content)
                    .font(.system(size: 11))
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 400)
    }
}
