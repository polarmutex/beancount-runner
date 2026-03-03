use beancount_parser_lima::{
    Amount as LimaAmount, Balance as LimaBalance, Close as LimaClose, Commodity as LimaCommodity,
    Custom as LimaCustom, Directive as LimaDirective, DirectiveVariant, Document as LimaDocument,
    Event as LimaEvent, Note as LimaNote, Open as LimaOpen, Pad as LimaPad, Posting as LimaPosting,
    Price as LimaPrice, Query as LimaQuery, Spanned, Transaction as LimaTransaction,
};
use crate::beancount;
use std::collections::HashMap;

// Date is from the time crate, re-exported by beancount_parser_lima
type LimaDate = time::Date;

/// Convert a lima parser directive to our protobuf directive
pub fn convert_directive(directive: &Spanned<LimaDirective>) -> Result<beancount::Directive, String> {
    let date = convert_date(directive.date());
    let metadata = convert_metadata(directive.metadata());
    let location = Some(convert_location(directive.span()));

    let directive_type = match directive.variant() {
        DirectiveVariant::Transaction(txn) => {
            Some(beancount::directive::DirectiveType::Transaction(
                convert_transaction(txn, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Balance(bal) => {
            Some(beancount::directive::DirectiveType::Balance(
                convert_balance(bal, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Open(open) => {
            Some(beancount::directive::DirectiveType::Open(
                convert_open(open, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Close(close) => {
            Some(beancount::directive::DirectiveType::Close(
                convert_close(close, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Commodity(commodity) => {
            Some(beancount::directive::DirectiveType::Commodity(
                convert_commodity(commodity, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Pad(pad) => {
            Some(beancount::directive::DirectiveType::Pad(
                convert_pad(pad, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Note(note) => {
            Some(beancount::directive::DirectiveType::Note(
                convert_note(note, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Document(doc) => {
            Some(beancount::directive::DirectiveType::Document(
                convert_document(doc, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Price(price) => {
            Some(beancount::directive::DirectiveType::Price(
                convert_price(price, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Event(event) => {
            Some(beancount::directive::DirectiveType::Event(
                convert_event(event, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Query(query) => {
            Some(beancount::directive::DirectiveType::Query(
                convert_query(query, &date, &metadata, location.clone())?
            ))
        }
        DirectiveVariant::Custom(custom) => {
            Some(beancount::directive::DirectiveType::Custom(
                convert_custom(custom, &date, &metadata, location.clone())?
            ))
        }
    };

    Ok(beancount::Directive { directive_type })
}

/// Convert a lima Date to protobuf Date
fn convert_date(date: &Spanned<LimaDate>) -> beancount::Date {
    beancount::Date {
        year: date.year() as i32,
        month: date.month() as i32,
        day: date.day() as i32,
    }
}

/// Convert a lima Amount to protobuf Amount
fn convert_amount(amount: &Spanned<LimaAmount>) -> beancount::Amount {
    beancount::Amount {
        number: amount.number().value().to_string(),
        currency: amount.currency().to_string(),
    }
}

/// Convert lima Metadata to protobuf Metadata
fn convert_metadata(metadata: &beancount_parser_lima::Metadata) -> beancount::Metadata {
    let mut entries = HashMap::new();

    // Convert key-value pairs
    for (key, value) in metadata.key_values() {
        let key_str = key.to_string();
        let meta_value = convert_metadata_value(value);
        entries.insert(key_str, meta_value);
    }

    // Add tags as metadata entries with true bool values
    for tag in metadata.tags() {
        let tag_key = format!("tag_{}", tag);
        entries.insert(
            tag_key,
            beancount::MetadataValue {
                value: Some(beancount::metadata_value::Value::BoolValue(true)),
            },
        );
    }

    // Add links as metadata entries
    for link in metadata.links() {
        let link_key = format!("link_{}", link);
        entries.insert(
            link_key,
            beancount::MetadataValue {
                value: Some(beancount::metadata_value::Value::StringValue(
                    link.to_string(),
                )),
            },
        );
    }

    beancount::Metadata { entries }
}

/// Convert lima MetaValue to protobuf MetadataValue
fn convert_metadata_value(
    value: &Spanned<beancount_parser_lima::MetaValue>,
) -> beancount::MetadataValue {
    use beancount_parser_lima::{MetaValue, SimpleValue};

    let proto_value = match value.item() {
        MetaValue::Simple(simple) => match simple {
            SimpleValue::String(s) => {
                Some(beancount::metadata_value::Value::StringValue(s.to_string()))
            }
            SimpleValue::Bool(b) => Some(beancount::metadata_value::Value::BoolValue(*b)),
            SimpleValue::Date(date) => {
                Some(beancount::metadata_value::Value::DateValue(beancount::Date {
                    year: date.year() as i32,
                    month: date.month() as i32,
                    day: date.day() as i32,
                }))
            }
            SimpleValue::Account(acc) => {
                Some(beancount::metadata_value::Value::StringValue(acc.to_string()))
            }
            SimpleValue::Tag(tag) => {
                Some(beancount::metadata_value::Value::StringValue(tag.to_string()))
            }
            SimpleValue::Currency(curr) => {
                Some(beancount::metadata_value::Value::StringValue(curr.to_string()))
            }
            SimpleValue::Link(link) => {
                Some(beancount::metadata_value::Value::StringValue(link.to_string()))
            }
            SimpleValue::Expr(expr) => {
                Some(beancount::metadata_value::Value::StringValue(expr.to_string()))
            }
            SimpleValue::Null => None,
        },
        MetaValue::Amount(amt) => Some(beancount::metadata_value::Value::AmountValue(
            beancount::Amount {
                number: amt.number().value().to_string(),
                currency: amt.currency().to_string(),
            },
        )),
    };

    beancount::MetadataValue { value: proto_value }
}

/// Convert a span to a Location
fn convert_location(_span: &beancount_parser_lima::Span) -> beancount::Location {
    // Span is from chumsky, we need to use its trait methods
    // For now, just use a placeholder since we don't have direct access to the source path
    beancount::Location {
        filename: "unknown".to_string(),
        line: 0,
        column: 0,
    }
}

/// Convert a lima Flag to string
fn convert_flag(flag: &Spanned<beancount_parser_lima::Flag>) -> String {
    use beancount_parser_lima::Flag;
    match **flag {
        Flag::Asterisk => "*".to_string(),
        Flag::Exclamation => "!".to_string(),
        Flag::Ampersand => "&".to_string(),
        Flag::Hash => "#".to_string(),
        Flag::Question => "?".to_string(),
        Flag::Percent => "%".to_string(),
        Flag::Letter(c) => c.char().to_string(),
    }
}

/// Convert a Transaction
fn convert_transaction(
    txn: &LimaTransaction,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Transaction, String> {
    let flag = Some(convert_flag(txn.flag()));
    let payee = txn.payee().map(|p| p.to_string());
    let narration = txn.narration().map(|n| n.to_string()).unwrap_or_default();

    // Extract tags and links from metadata
    let mut tags = Vec::new();
    let mut links = Vec::new();
    for (key, _value) in &metadata.entries {
        if let Some(tag_name) = key.strip_prefix("tag_") {
            tags.push(tag_name.to_string());
        } else if let Some(link_name) = key.strip_prefix("link_") {
            links.push(link_name.to_string());
        }
    }

    let postings: Result<Vec<_>, _> = txn.postings().map(convert_posting).collect();

    Ok(beancount::Transaction {
        date: Some(date.clone()),
        flag,
        payee,
        narration,
        tags,
        links,
        postings: postings?,
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert a Posting
fn convert_posting(posting: &Spanned<LimaPosting>) -> Result<beancount::Posting, String> {
    let account = posting.account().to_string();

    let amount = if let Some(amt) = posting.amount() {
        if let Some(currency) = posting.currency() {
            Some(beancount::Amount {
                number: amt.value().to_string(),
                currency: currency.to_string(),
            })
        } else {
            return Err("Posting has amount but no currency".to_string());
        }
    } else {
        None
    };

    // TODO: Handle cost_spec and price_annotation properly
    let cost = None;
    let price = None;

    let flag = posting.flag().map(|f| convert_flag(f));
    let metadata = Some(convert_metadata(posting.metadata()));

    Ok(beancount::Posting {
        account,
        amount,
        cost,
        price,
        flag,
        metadata,
    })
}

/// Convert a Balance directive
fn convert_balance(
    bal: &LimaBalance,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Balance, String> {
    let account = bal.account().to_string();
    let amount = convert_amount(bal.atol().amount());
    let tolerance = bal.atol().tolerance().map(|tol| beancount::Amount {
        number: tol.to_string(),
        currency: bal.atol().amount().currency().to_string(),
    });

    Ok(beancount::Balance {
        date: Some(date.clone()),
        account,
        amount: Some(amount),
        tolerance,
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert an Open directive
fn convert_open(
    open: &LimaOpen,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Open, String> {
    let account = open.account().to_string();
    let currencies: Vec<String> = open.currencies().map(|c| c.to_string()).collect();
    let booking_method = open.booking().map(|b| b.to_string());

    Ok(beancount::Open {
        date: Some(date.clone()),
        account,
        currencies,
        booking_method,
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert a Close directive
fn convert_close(
    close: &LimaClose,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Close, String> {
    let account = close.account().to_string();

    Ok(beancount::Close {
        date: Some(date.clone()),
        account,
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert a Commodity directive
fn convert_commodity(
    commodity: &LimaCommodity,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Commodity, String> {
    let currency = commodity.currency().to_string();

    Ok(beancount::Commodity {
        date: Some(date.clone()),
        currency,
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert a Pad directive
fn convert_pad(
    pad: &LimaPad,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Pad, String> {
    let account = pad.account().to_string();
    let source_account = pad.source().to_string();

    Ok(beancount::Pad {
        date: Some(date.clone()),
        account,
        source_account,
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert a Note directive
fn convert_note(
    note: &LimaNote,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Note, String> {
    let account = note.account().to_string();
    let comment = note.comment().to_string();

    Ok(beancount::Note {
        date: Some(date.clone()),
        account,
        comment,
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert a Document directive
fn convert_document(
    doc: &LimaDocument,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Document, String> {
    let account = doc.account().to_string();
    let path = doc.path().to_string();

    // Extract tags from metadata
    let mut tags = Vec::new();
    for (key, _value) in &metadata.entries {
        if let Some(tag_name) = key.strip_prefix("tag_") {
            tags.push(tag_name.to_string());
        }
    }

    Ok(beancount::Document {
        date: Some(date.clone()),
        account,
        path,
        tags,
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert a Price directive
fn convert_price(
    price: &LimaPrice,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Price, String> {
    let currency = price.currency().to_string();
    let amount = convert_amount(price.amount());

    Ok(beancount::Price {
        date: Some(date.clone()),
        currency,
        amount: Some(amount),
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert an Event directive
fn convert_event(
    event: &LimaEvent,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Event, String> {
    let event_type = event.event_type().to_string();
    let description = event.description().to_string();

    Ok(beancount::Event {
        date: Some(date.clone()),
        r#type: event_type,
        description,
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert a Query directive
fn convert_query(
    query: &LimaQuery,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Query, String> {
    let name = query.name().to_string();
    let query_string = query.content().to_string();

    Ok(beancount::Query {
        date: Some(date.clone()),
        name,
        query_string,
        metadata: Some(metadata.clone()),
        location,
    })
}

/// Convert a Custom directive
fn convert_custom(
    custom: &LimaCustom,
    date: &beancount::Date,
    metadata: &beancount::Metadata,
    location: Option<beancount::Location>,
) -> Result<beancount::Custom, String> {
    let custom_type = custom.type_().to_string();

    // TODO: Convert custom values properly - for now just leave empty
    let values = Vec::new();

    Ok(beancount::Custom {
        date: Some(date.clone()),
        r#type: custom_type,
        values,
        metadata: Some(metadata.clone()),
        location,
    })
}
