use wasm_bindgen::prelude::*;
use wasm_bindgen::JsValue;
use web_sys::console;

#[wasm_bindgen]
pub struct ExoGridWasm {
    host: String,
    port: u16,
}

#[wasm_bindgen]
impl ExoGridWasm {
    #[wasm_bindgen(constructor)]
    pub fn new(host: String, port: u16) -> ExoGridWasm {
        ExoGridWasm { host, port }
    }

    #[wasm_bindgen]
    pub async fn fetch_matrix(&self, ticker: &str, timeframe: &str) -> Result<JsValue, JsValue> {
        let url = format!(
            "http://{}:{}/api/matrix?ticker={}&timeframe={}",
            self.host, self.port, ticker, timeframe
        );

        let window = web_sys::window().ok_or("No window")?;
        let resp = wasm_bindgen_futures::JsFuture::from(window.fetch_with_str(&url))
            .await
            .map_err(|_| "Fetch failed")?;

        let resp: web_sys::Response = resp.dyn_into().map_err(|_| "Response conversion failed")?;
        let json = wasm_bindgen_futures::JsFuture::from(resp.json().map_err(|_| "JSON failed")?)
            .await
            .map_err(|_| "JSON await failed")?;

        Ok(json)
    }

    #[wasm_bindgen]
    pub async fn fetch_ticks(&self) -> Result<JsValue, JsValue> {
        let url = format!("http://{}:{}/api/ticks", self.host, self.port);

        let window = web_sys::window().ok_or("No window")?;
        let resp = wasm_bindgen_futures::JsFuture::from(window.fetch_with_str(&url))
            .await
            .map_err(|_| "Fetch failed")?;

        let resp: web_sys::Response = resp.dyn_into().map_err(|_| "Response conversion failed")?;
        let json = wasm_bindgen_futures::JsFuture::from(resp.json().map_err(|_| "JSON failed")?)
            .await
            .map_err(|_| "JSON await failed")?;

        Ok(json)
    }

    #[wasm_bindgen]
    pub fn log(&self, msg: &str) {
        console::log_1(&format!("[ExoGrid] {}", msg).into());
    }
}
