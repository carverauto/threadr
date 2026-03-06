use std::alloc::{alloc, dealloc, Layout};
use std::slice;

#[unsafe(no_mangle)]
pub extern "C" fn alloc_bytes(len: usize) -> *mut u8 {
    if len == 0 {
        return std::ptr::null_mut();
    }

    let layout = match Layout::array::<u8>(len) {
        Ok(layout) => layout,
        Err(_) => return std::ptr::null_mut(),
    };

    unsafe { alloc(layout) }
}

#[unsafe(no_mangle)]
pub extern "C" fn free_bytes(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }

    let layout = match Layout::array::<u8>(len) {
        Ok(layout) => layout,
        Err(_) => return,
    };

    unsafe { dealloc(ptr, layout) }
}

#[unsafe(no_mangle)]
pub extern "C" fn compute_state_mask(
    states_ptr: *const u8,
    states_len: usize,
    root_enabled: u8,
    affected_enabled: u8,
    healthy_enabled: u8,
    unknown_enabled: u8,
    out_mask_ptr: *mut u8,
) {
    if states_ptr.is_null() || out_mask_ptr.is_null() {
        return;
    }

    let states = unsafe { slice::from_raw_parts(states_ptr, states_len) };
    let out = unsafe { slice::from_raw_parts_mut(out_mask_ptr, states_len) };

    for (idx, state) in states.iter().enumerate() {
        let enabled = match *state {
            0 => root_enabled != 0,
            1 => affected_enabled != 0,
            2 => healthy_enabled != 0,
            _ => unknown_enabled != 0,
        };

        out[idx] = if enabled { 1 } else { 0 };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn compute_three_hop_mask(
    node_count: usize,
    edge_src_ptr: *const u32,
    edge_dst_ptr: *const u32,
    edge_len: usize,
    start_node: usize,
    out_mask_ptr: *mut u8,
) {
    if edge_src_ptr.is_null() || edge_dst_ptr.is_null() || out_mask_ptr.is_null() {
        return;
    }
    if start_node >= node_count {
        return;
    }

    let src = unsafe { slice::from_raw_parts(edge_src_ptr, edge_len) };
    let dst = unsafe { slice::from_raw_parts(edge_dst_ptr, edge_len) };
    let out = unsafe { slice::from_raw_parts_mut(out_mask_ptr, node_count) };

    out.fill(0);

    let mut frontier = vec![start_node];
    out[start_node] = 1;

    for _ in 0..3 {
        if frontier.is_empty() {
            break;
        }

        let mut next = Vec::new();

        for node in frontier {
            for i in 0..edge_len {
                let a = src[i] as usize;
                let b = dst[i] as usize;

                if a == node && b < node_count && out[b] == 0 {
                    out[b] = 1;
                    next.push(b);
                } else if b == node && a < node_count && out[a] == 0 {
                    out[a] = 1;
                    next.push(a);
                }
            }
        }

        frontier = next;
    }
}
