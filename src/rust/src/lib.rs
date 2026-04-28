use extendr_api::prelude::*;
use soccer_rs::{
    get_classification_system, get_crosswalk, CodedJobDescription, Crosswalk, ModelType, MyError,
    SoccerBuilder, SoccerPipeline, MODEL_CONFIG,
};
use std::{cmp::min, result::Result, sync::Arc};

/// This is my function documentation
/// @export
#[extendr]
fn soccer_net(df: Dataframe<Robj>, n: usize, block_size: Option<usize>) -> Result<Robj, MyError> {
    // need to deal with the version...
    let config = MODEL_CONFIG
        .get_config(&ModelType::SOCcerNET, "1.0.0")
        .unwrap();
    let mut pipeline = SoccerPipeline::build(config).unwrap();

    // this needs to be part of the classification system...
    let output_classification_system_name = "soc2010";

    // Get References to the R strings...
    let id_strings: Strings = get_strings(&df, "Id")?;
    let job_title_strings: Strings = get_strings(&df, "JobTitle")?;
    let job_task_strings: Strings = get_strings(&df, "JobTask")?;

    // convert it to a Vec<&str> you need to maintain the Strings...
    let ids = make_str(&id_strings);
    let job_titles = make_str(&job_title_strings);
    let job_tasks = make_str(&job_task_strings);
    let effective_block_size = block_size.unwrap_or(ids.len());

    let mut prior: Vec<Vec<u16>> = vec![vec![]; ids.len()];
    adjust_prior(
        &df,
        "soc1980",
        &mut prior,
        output_classification_system_name,
    );
    adjust_prior(
        &df,
        "noc2011",
        &mut prior,
        output_classification_system_name,
    );
    adjust_prior(
        &df,
        "isco1988",
        &mut prior,
        output_classification_system_name,
    );

    // freeze the prior into a box...
    let prior: Vec<Box<[u16]>> = prior.into_iter().map(|v| v.into_boxed_slice()).collect();

    let all_results: Result<Vec<_>, MyError> = ids
        .chunks(effective_block_size)
        .enumerate()
        .map(|(chunk_indx, id_block)| {
            let indx_start = chunk_indx * effective_block_size;
            let indx_end = min(indx_start + id_block.len(), ids.len());
            pipeline.predict_from_columns(
                id_block,
                &job_titles[indx_start..indx_end],
                Some(&job_tasks[indx_start..indx_end]),
                &prior[indx_start..indx_end],
            )
        })
        .collect();
    let all_results = all_results?.into_iter().flatten().collect();

    //let soccer_results = pipeline.predict_from_columns(&ids, &job_titles, Some(&job_tasks), &prior)?;
    build_result_df(all_results, n, output_classification_system_name)
}

/// This is my function documentation
/// @export
#[extendr]
fn clips(df: Dataframe<Robj>, n: usize, block_size: Option<usize>) -> Result<Robj, MyError> {
    let config = MODEL_CONFIG.get_config(&ModelType::CLIPS, "1.0.0").unwrap();
    let mut pipeline = SoccerPipeline::build(config).unwrap();

    // this needs to be part of the classification system...
    let output_classification_system_name = "naics2022";

    // Get References to the R strings...
    let id_strings: Strings = get_strings(&df, "Id")?;
    let products_services_strings: Strings = get_strings(&df, "products_services")?;

    // convert it to a Vec<&str> you need to maintain the Strings...
    let ids = make_str(&id_strings);
    let products_services = make_str(&products_services_strings);
    let effective_block_size = block_size.unwrap_or(ids.len());

    let mut prior: Vec<Vec<u16>> = vec![vec![]; ids.len()];
    adjust_prior(
        &df,
        "sic1987",
        &mut prior,
        output_classification_system_name,
    );

    // freeze the prior into a box...
    let prior: Vec<Box<[u16]>> = prior.into_iter().map(|v| v.into_boxed_slice()).collect();

    let all_results: Result<Vec<_>, MyError> = ids
        .chunks(effective_block_size)
        .enumerate()
        .map(|(chunk_indx, id_block)| {
            let indx_start = chunk_indx * effective_block_size;
            let indx_end = min(indx_start + id_block.len(), ids.len());
            pipeline.predict_from_columns(
                id_block,
                &products_services[indx_start..indx_end],
                None,
                &prior[indx_start..indx_end],
            )
        })
        .collect();

    let all_results = all_results?.into_iter().flatten().collect();

    //let soccer_results = pipeline.predict_from_columns(&ids, &products_services, None, &prior)?;
    build_result_df(all_results, n, output_classification_system_name)
}

fn get_strings(df: &Dataframe<Robj>, col_name: &str) -> Result<Strings, MyError> {
    Ok(df
        .dollar(col_name)
        .map_err(|e| MyError::SoccerError(e.to_string()))?
        .try_into()
        .map_err(|e: Error| MyError::SoccerError(e.to_string()))?)
}

fn make_str<'a>(string: &'a Strings) -> Vec<&'a str> {
    string
        .iter()
        .map(|s| if s.is_na() { "" } else { s.as_ref() })
        .collect()
}

fn adjust_prior(
    df: &Dataframe<Robj>,
    col_name: &str,
    prior: &mut Vec<Vec<u16>>,
    output_classification_system: &str,
) {
    let mut col_names = match df.names() {
        Some(names) => names,
        None => return, // If it has no names, it's not a valid dataframe for us
    };
    if !col_names.any(|name| name == col_name) {
        return; // The column is missing. Exit silently.
    }

    let Ok(column) = df.dollar(col_name) else {
        return;
    };
    let Ok(col): Result<List, _> = column.try_into() else {
        return;
    };
    let Ok(crosswalk): Result<Arc<Crosswalk>, _> =
        get_crosswalk(col_name, output_classification_system)
    else {
        return;
    };

    col.iter().enumerate().for_each(|(row_indx, (_, v))| {
        if let Some(prior_row) = prior.get_mut(row_indx) {
            if let Ok(obj_value) = Strings::try_from(v) {
                let codes: Vec<&str> = obj_value
                    .iter()
                    .filter_map(|r_str| {
                        if r_str.is_na() {
                            None
                        } else {
                            Some(r_str.as_ref())
                        }
                    })
                    .collect();
                if !codes.is_empty() {
                    crosswalk.crosswalk_into(&codes, prior_row);
                }
            }
        };
    });
}

fn build_result_df(
    soccer_results: Vec<CodedJobDescription>,
    n: usize,
    output_classification_system_name: &str,
) -> Result<Robj, MyError> {
    let output_classification_system =
        get_classification_system(output_classification_system_name)?;
    let n: usize = min(n, output_classification_system.len());
    let mut id_column: Vec<String> = Vec::with_capacity(soccer_results.len());
    let mut row_names: Vec<i32> = Vec::with_capacity(soccer_results.len());
    let mut code_columns: Vec<Vec<Option<String>>> =
        vec![Vec::with_capacity(soccer_results.len()); n];
    let mut title_columns: Vec<Vec<Option<String>>> =
        vec![Vec::with_capacity(soccer_results.len()); n];
    let mut score_columns: Vec<Vec<f64>> = vec![Vec::with_capacity(soccer_results.len()); n];
    // use up the soccer_results...
    soccer_results
        .into_iter()
        .enumerate()
        // for each row...
        .for_each(|(row_indx, job)| {
            row_names.push((row_indx + 1) as i32);
            id_column.push(job.id.into_owned());
            // for the top N outputs...
            job.scored_code_index
                .iter()
                .take(n)
                .enumerate()
                .for_each(|(rank, si)| {
                    if let Some((code, title)) =
                        output_classification_system.get_code_title(si.0 as u32)
                    {
                        code_columns[rank].push(Some(code.to_string()));
                        title_columns[rank].push(Some(title.to_string()));
                        score_columns[rank].push(si.1 as f64);
                    } else {
                        code_columns[rank].push(None);
                        title_columns[rank].push(None);
                        score_columns[rank].push(f64::NAN);
                    }
                });
        });

    let mut df_pairs: Vec<(String, Robj)> = Vec::new();
    df_pairs.push(("Id".to_string(), id_column.into_robj()));
    for i in 0..n {
        let rank = i + 1;
        df_pairs.push((
            format!("{}_{}", output_classification_system_name, rank),
            code_columns[i].clone().into_robj(),
        ));
        df_pairs.push((
            format!("{}_title_{}", output_classification_system_name, rank),
            title_columns[i].clone().into_robj(),
        ));
        df_pairs.push((
            format!("score_{}", rank),
            score_columns[i].clone().into_robj(),
        ));
    }
    let mut final_df = List::from_pairs(df_pairs).into_robj();

    final_df
        .set_class(&["tbl_df", "tbl", "data.frame"])
        .map_err(|e| MyError::OutputError(e.to_string()))?;
    final_df
        .set_attrib("row.names", row_names)
        .map_err(|e| MyError::OutputError(e.to_string()))?;
    Ok(final_df)
}

// 2. The Macro that tells R what functions exist
extendr_module! {
    mod soccerrsr;
    fn soccer_net;
    fn clips;
}

#[cfg(test)]
mod tests {
    use super::*;
    //use extendr_api::{c, list, data_frame, test};

    #[test]
    fn test_soccernet_api() {
        test! {
            let robj = R!(
                data.frame(
                    Id = c("SN-1", "SN-2"),
                    JobTitle = c("doctor", "lawyer"),
                    JobTask = c("treat patients", "legal advice"),
                    soc1980 = I(list("261", "211")) // <-- I() is the magic shield!
                )
            ).unwrap();
            let df:Dataframe<Robj> = robj.try_into()?;

            let x = soccer_net(df,4,Some(100)).unwrap();

            let expected_score_j1 = [0.3232,0.1386,0.0980,0.0300];
            let expected_score_j2 = [0.9996,0.0064,0.0033,0.0022];
            // test score1
            expected_score_j1.iter()
                .zip(expected_score_j2.iter())
                .enumerate()
                .for_each(|(i,(xj1,xj2))| {
                    let res = x.dollar(format!("score_{}",i+1)).unwrap();
                    let res = res.as_real_slice().unwrap();
                    println!("{}: {:?} {} {}\t{} {}",i+1,res,xj1,xj2,(res[0]-xj1).abs(),(res[1]-xj2).abs());
                    assert!( (res[0]-xj1).abs()<1e-4 );
                    assert!( (res[1]-xj2).abs()<1e-4 );
                });
        }
    }

    #[test]
    fn test_soccernet_isco() {
        test! {
            let robj = R!(
                data.frame(
                    Id = c("SN-1", "SN-2"),
                    JobTitle = c("doctor", "lawyer"),
                    JobTask = c("treat patients", "legal advice"),
                    isco1988 = I(list("3241", "2421")) // <-- I() is the magic shield!
                )
            ).unwrap();
            let df:Dataframe<Robj> = robj.try_into()?;

            let x = soccer_net(df,4,Some(100)).unwrap();
            println!("{:?}",x);

            let expected_score_j1 = [0.1449,0.1428,0.0916,0.0559];
            let expected_score_j2 = [0.9999,0.0046,0.0024,0.0020];
            // test score1
            expected_score_j1.iter()
                .zip(expected_score_j2.iter())
                .enumerate()
                .for_each(|(i,(xj1,xj2))| {
                    let res = x.dollar(format!("score_{}",i+1)).unwrap();
                    let res = res.as_real_slice().unwrap();
                    println!("{}: {:?} {} {}\t{} {}",i+1,res,xj1,xj2,(res[0]-xj1).abs(),(res[1]-xj2).abs());
                    assert!( (res[0]-xj1).abs()<1e-4 );
                    assert!( (res[1]-xj2).abs()<1e-4 );
                });
        }
    }

    #[test]
    fn test_soccernet_noc() {
        test! {
            let robj = R!(
                data.frame(
                    Id = c("SN-1", "SN-2"),
                    JobTitle = c("doctor", "lawyer"),
                    JobTask = c("treat patients", "legal advice"),
                    noc2011 = I(list("3112", "4112")) // <-- I() is the magic shield!
                )
            ).unwrap();
            let df:Dataframe<Robj> = robj.try_into()?;

            let x = soccer_net(df,4,Some(100)).unwrap();
            println!("{:?}",x);

            let expected_score_j1 = [0.1620,0.1296,0.1294,0.0886];
            let expected_score_j2 = [0.9999,0.0046,0.0024,0.0020];
            // test score1
            expected_score_j1.iter()
                .zip(expected_score_j2.iter())
                .enumerate()
                .for_each(|(i,(xj1,xj2))| {
                    let res = x.dollar(format!("score_{}",i+1)).unwrap();
                    let res = res.as_real_slice().unwrap();
                    println!("{}: {:?} {} {}\t{} {}",i+1,res,xj1,xj2,(res[0]-xj1).abs(),(res[1]-xj2).abs());
                    assert!( (res[0]-xj1).abs()<1e-4 );
                    assert!( (res[1]-xj2).abs()<1e-4 );
                });
        }
    }

    #[test]
    fn test_clips_api() {
        test! {
            let robj = R!(
                data.frame(
                    Id = c("RClipsTest-1", "RClipsTest-2"),
                    products_services = c("Software Engineer,Develop and maintain software applications",
                        "Full-service dental care, including routine checkups, cleanings, and cosmetic procedures"),
                    sic1987 = I(list("7372","8021"))
                )
            ).unwrap();
            let df:Dataframe<Robj> = robj.try_into()?;

            let x = clips(df,4,None).unwrap();
            let expected_score_j1 = [0.7416,0.1195,0.0904,0.0459];
            let expected_score_j2 = [0.9333,0.0181,0.0112,0.0046];
            // test score1
            expected_score_j1.iter()
                .zip(expected_score_j2.iter())
                .enumerate()
                .for_each(|(i,(xj1,xj2))| {
                    let res = x.dollar(format!("score_{}",i+1)).unwrap();
                    let res = res.as_real_slice().unwrap();
                    println!("{}: {:?} {} {}\t{} {}",i+1,res,xj1,xj2,(res[0]-xj1).abs(),(res[1]-xj2).abs());
                    assert!( (res[0]-xj1).abs()<1e-4 );
                    assert!( (res[1]-xj2).abs()<1e-4 );
                });
        }
    }
}
