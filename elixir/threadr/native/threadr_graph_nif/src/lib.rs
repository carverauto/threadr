use std::collections::HashMap;
use std::sync::Arc;

use arrow_array::{Float32Array, Int8Array, RecordBatch, StringArray, UInt32Array};
use arrow_ipc::writer::FileWriter;
use arrow_schema::{DataType, Field, Schema};
use roaring::RoaringBitmap;
use rustler::{Binary, Env, NifResult, OwnedBinary};

#[rustler::nif(schedule = "DirtyCpu")]
fn build_roaring_bitmaps<'a>(
    env: Env<'a>,
    states: Vec<u8>,
) -> NifResult<(
    Binary<'a>,
    Binary<'a>,
    Binary<'a>,
    Binary<'a>,
    (u32, u32, u32, u32),
)> {
    let mut root = RoaringBitmap::new();
    let mut affected = RoaringBitmap::new();
    let mut healthy = RoaringBitmap::new();
    let mut unknown = RoaringBitmap::new();

    for (idx, state) in states.iter().enumerate() {
        let value = idx as u32;
        match *state {
            0 => {
                root.insert(value);
            }
            1 => {
                affected.insert(value);
            }
            2 => {
                healthy.insert(value);
            }
            _ => {
                unknown.insert(value);
            }
        }
    }

    let root_count = root.len() as u32;
    let affected_count = affected.len() as u32;
    let healthy_count = healthy.len() as u32;
    let unknown_count = unknown.len() as u32;

    Ok((
        vec_into_binary(env, serialize_bitmap(&root)?)?,
        vec_into_binary(env, serialize_bitmap(&affected)?)?,
        vec_into_binary(env, serialize_bitmap(&healthy)?)?,
        vec_into_binary(env, serialize_bitmap(&unknown)?)?,
        (root_count, affected_count, healthy_count, unknown_count),
    ))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn encode_snapshot<'a>(
    env: Env<'a>,
    schema_version: u32,
    revision: u64,
    nodes: Vec<(f64, f64, u8, String, String, f64, String)>,
    edges: Vec<(u32, u32, u32, String, String)>,
    bitmap_sizes: Vec<u32>,
) -> NifResult<Binary<'a>> {
    let total_rows = nodes.len() + edges.len();
    let mut row_type = Vec::<i8>::with_capacity(total_rows);
    let mut node_x = Vec::<Option<f32>>::with_capacity(total_rows);
    let mut node_y = Vec::<Option<f32>>::with_capacity(total_rows);
    let mut node_state = Vec::<Option<u32>>::with_capacity(total_rows);
    let mut node_label = Vec::<Option<String>>::with_capacity(total_rows);
    let mut node_kind = Vec::<Option<String>>::with_capacity(total_rows);
    let mut node_size = Vec::<Option<f32>>::with_capacity(total_rows);
    let mut node_details = Vec::<Option<String>>::with_capacity(total_rows);
    let mut edge_source = Vec::<Option<u32>>::with_capacity(total_rows);
    let mut edge_target = Vec::<Option<u32>>::with_capacity(total_rows);
    let mut edge_weight = Vec::<Option<u32>>::with_capacity(total_rows);
    let mut edge_label = Vec::<Option<String>>::with_capacity(total_rows);
    let mut edge_kind = Vec::<Option<String>>::with_capacity(total_rows);

    for (x, y, state, label, kind, size, details) in nodes {
        row_type.push(0);
        node_x.push(Some(x as f32));
        node_y.push(Some(y as f32));
        node_state.push(Some(state as u32));
        node_label.push(Some(label));
        node_kind.push(Some(kind));
        node_size.push(Some(size as f32));
        node_details.push(Some(details));
        edge_source.push(None);
        edge_target.push(None);
        edge_weight.push(None);
        edge_label.push(None);
        edge_kind.push(None);
    }

    for (source, target, weight, label, kind) in edges {
        row_type.push(1);
        node_x.push(None);
        node_y.push(None);
        node_state.push(None);
        node_label.push(None);
        node_kind.push(None);
        node_size.push(None);
        node_details.push(None);
        edge_source.push(Some(source));
        edge_target.push(Some(target));
        edge_weight.push(Some(weight));
        edge_label.push(Some(label));
        edge_kind.push(Some(kind));
    }

    let mut metadata = HashMap::new();
    metadata.insert("schema_version".to_string(), schema_version.to_string());
    metadata.insert("revision".to_string(), revision.to_string());

    if bitmap_sizes.len() == 4 {
        metadata.insert("root_bitmap_bytes".to_string(), bitmap_sizes[0].to_string());
        metadata.insert(
            "affected_bitmap_bytes".to_string(),
            bitmap_sizes[1].to_string(),
        );
        metadata.insert("healthy_bitmap_bytes".to_string(), bitmap_sizes[2].to_string());
        metadata.insert("unknown_bitmap_bytes".to_string(), bitmap_sizes[3].to_string());
    }

    let schema = Arc::new(Schema::new_with_metadata(
        vec![
            Field::new("row_type", DataType::Int8, false),
            Field::new("node_x", DataType::Float32, true),
            Field::new("node_y", DataType::Float32, true),
            Field::new("node_state", DataType::UInt32, true),
            Field::new("node_label", DataType::Utf8, true),
            Field::new("node_kind", DataType::Utf8, true),
            Field::new("node_size", DataType::Float32, true),
            Field::new("node_details", DataType::Utf8, true),
            Field::new("edge_source", DataType::UInt32, true),
            Field::new("edge_target", DataType::UInt32, true),
            Field::new("edge_weight", DataType::UInt32, true),
            Field::new("edge_label", DataType::Utf8, true),
            Field::new("edge_kind", DataType::Utf8, true),
            Field::new("snapshot_schema_version", DataType::UInt32, false),
            Field::new("snapshot_revision", DataType::UInt32, false),
        ],
        metadata,
    ));

    let schema_version_col = vec![schema_version; total_rows];
    let revision_col = vec![(revision & 0xFFFF_FFFF) as u32; total_rows];

    let batch = RecordBatch::try_new(
        Arc::clone(&schema),
        vec![
            Arc::new(Int8Array::from(row_type)),
            Arc::new(Float32Array::from(node_x)),
            Arc::new(Float32Array::from(node_y)),
            Arc::new(UInt32Array::from(node_state)),
            Arc::new(StringArray::from(node_label)),
            Arc::new(StringArray::from(node_kind)),
            Arc::new(Float32Array::from(node_size)),
            Arc::new(StringArray::from(node_details)),
            Arc::new(UInt32Array::from(edge_source)),
            Arc::new(UInt32Array::from(edge_target)),
            Arc::new(UInt32Array::from(edge_weight)),
            Arc::new(StringArray::from(edge_label)),
            Arc::new(StringArray::from(edge_kind)),
            Arc::new(UInt32Array::from(schema_version_col)),
            Arc::new(UInt32Array::from(revision_col)),
        ],
    )
    .map_err(|_| rustler::Error::BadArg)?;

    let mut payload = Vec::new();
    {
        let mut writer =
            FileWriter::try_new(&mut payload, &schema).map_err(|_| rustler::Error::BadArg)?;
        writer.write(&batch).map_err(|_| rustler::Error::BadArg)?;
        writer.finish().map_err(|_| rustler::Error::BadArg)?;
    }

    vec_into_binary(env, payload)
}

fn serialize_bitmap(bitmap: &RoaringBitmap) -> Result<Vec<u8>, rustler::Error> {
    let mut out = Vec::new();
    bitmap
        .serialize_into(&mut out)
        .map_err(|_| rustler::Error::BadArg)?;
    Ok(out)
}

fn vec_into_binary<'a>(env: Env<'a>, bytes: Vec<u8>) -> Result<Binary<'a>, rustler::Error> {
    let mut out = OwnedBinary::new(bytes.len()).ok_or(rustler::Error::BadArg)?;
    out.as_mut_slice().copy_from_slice(&bytes);
    Ok(Binary::from_owned(out, env))
}

rustler::init!("Elixir.Threadr.TenantData.GraphSnapshot.Native");
