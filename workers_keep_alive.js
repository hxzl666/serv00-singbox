// ============================================================================
// Cloudflare Workers 节点/隧道保活与 Telegram 推送脚本
// ============================================================================
// 作用:
//   1. 定期 Ping (HTTP GET) 您的 Argo 隧道域名或 VPS 上的文件订阅链接，防止隧道闲置断连
//   2. 在每次巡检后，将所有被保活节点的在线状态通过 Telegram Bot 发送给您
// ============================================================================

// [默认配置区] 
// 建议优先在 Cloudflare Workers 后台的 Settings -> Variables 中添加同名环境变量，以保证安全！
const DEFAULT_CONFIG = {
  // 需要保活的节点/隧道域名或订阅文件链接 (支持多个)
  URLS: [
    "https://your-argo-subdomain.trycloudflare.com/sub.txt",
    "https://your-another-server-domain.com"
  ],

  // Telegram 通知配置 (若不需要通知，可保留为空字符串)
  TELEGRAM_BOT_TOKEN: "", // 填入您的 Telegram Bot Token (例如 123456:ABC-DEF...)
  TELEGRAM_CHAT_ID: ""    // 填入您的 Telegram Chat ID (例如 123456789)
};

// 保活逻辑主函数
async function doKeepAlive(env) {
  // 优先从环境变量获取
  let urls = [];
  if (env && env.URLS) {
    // 环境变量支持半角逗号分隔的多个 URL
    urls = env.URLS.split(",").map(u => u.trim()).filter(Boolean);
  } else {
    urls = DEFAULT_CONFIG.URLS;
  }

  const botToken = (env && env.TELEGRAM_BOT_TOKEN) || DEFAULT_CONFIG.TELEGRAM_BOT_TOKEN;
  const chatId = (env && env.TELEGRAM_CHAT_ID) || DEFAULT_CONFIG.TELEGRAM_CHAT_ID;

  if (urls.length === 0) {
    console.log("未配置任何需要保活的 URL 列表。");
    return { successCount: 0, failCount: 0, message: "No URLs configured" };
  }

  let successCount = 0;
  let failCount = 0;
  let detailMessage = "";

  for (let url of urls) {
    if (!url.startsWith("http")) {
      url = "https://" + url;
    }
    
    const startTime = Date.now();
    try {
      // 设定 10 秒超时
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 10000);

      const response = await fetch(url, {
        method: "GET",
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        },
        signal: controller.signal
      });

      clearTimeout(timeoutId);
      const latency = Date.now() - startTime;

      if (response.status >= 200 && response.status < 400) {
        detailMessage += `✅ *[OK]* [链接](${url})\n- 状态码: \`${response.status}\` | 延迟: \`${latency}ms\`\n\n`;
        successCount++;
      } else {
        detailMessage += `⚠️ *[WARN]* [链接](${url})\n- 状态码: \`${response.status}\` | 延迟: \`${latency}ms\`\n\n`;
        failCount++;
      }
    } catch (err) {
      const latency = Date.now() - startTime;
      let errMsg = err.message;
      if (err.name === "AbortError") {
        errMsg = "连接超时 (10s)";
      }
      detailMessage += `❌ *[FAIL]* [链接](${url})\n- 异常: \`${errMsg}\` | 耗时: \`${latency}ms\`\n\n`;
      failCount++;
    }
  }

  // 组装 Telegram 通知内容
  let reportMessage = "🔔 *Cloudflare Workers 节点保活报告*\n\n";
  reportMessage += `📊 *统计汇总*:\n- 正常: \`${successCount}\` 个\n- 异常: \`${failCount}\` 个\n- 总计: \`${urls.length}\` 个\n\n`;
  reportMessage += `📝 *保活详情*:\n${detailMessage}`;

  // 发送 TG 消息
  if (botToken && chatId) {
    const tgUrl = `https://api.telegram.org/bot${botToken}/sendMessage`;
    try {
      await fetch(tgUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          chat_id: chatId,
          text: reportMessage,
          parse_mode: "Markdown",
          disable_web_page_preview: true
        })
      });
      console.log("Telegram 通知发送成功！");
    } catch (e) {
      console.error("发送 Telegram 通知失败:", e);
    }
  } else {
    console.log("未配置 Telegram 机器人参数，跳过推送通知。");
  }

  return { successCount, failCount };
}

// 导出模块对接 Workers 触发器
export default {
  // 1. 定期 Cron 触发器执行
  async scheduled(event, env, ctx) {
    ctx.waitUntil(doKeepAlive(env));
  },
  
  // 2. 网页/手动 fetch 触发执行 (用于方便测试)
  async fetch(request, env, ctx) {
    const result = await doKeepAlive(env);
    return new Response(JSON.stringify({
      status: "success",
      message: "Keep-alive trigger complete.",
      stats: result
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
};
